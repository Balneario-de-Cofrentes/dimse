defmodule Dimse.Association do
  @moduledoc """
  GenServer managing a single DICOM association lifecycle.

  Implements the DICOM Upper Layer state machine defined in PS3.8 Section 9.2.
  Each TCP connection spawns one Association process that owns the socket and
  manages the full lifecycle: negotiation, message exchange, and release/abort.

  ## Modes

  - **SCP mode**: Started by `Dimse.ConnectionHandler` when a TCP connection is
    accepted. Waits for A-ASSOCIATE-RQ, negotiates, then handles DIMSE commands.
  - **SCU mode**: Started by `Dimse.Scu.open/3` to connect to a remote SCP.
    Sends A-ASSOCIATE-RQ, waits for AC, then executes DIMSE operations.
  """

  use GenServer

  alias Dimse.{Pdu, Command, Message, Telemetry}
  alias Dimse.Pdu.{Encoder, Decoder}
  alias Dimse.Association.{State, Config, Negotiation}
  alias Dimse.Command.Fields

  @implementation_uid "1.2.826.0.1.3680043.8.498.1"
  @implementation_version "DIMSE_0.2.0"

  @default_transfer_syntaxes MapSet.new([
                               "1.2.840.10008.1.2",
                               "1.2.840.10008.1.2.1"
                             ])

  # --- Public API ---

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @doc """
  Sends a DIMSE command on the association and waits for the response.

  Used by SCU modules (e.g., `Dimse.Scu.Echo`) to execute operations.
  """
  @spec request(pid(), map(), binary() | nil, timeout()) ::
          {:ok, map(), binary() | nil} | {:error, term()}
  def request(pid, command_set, data \\ nil, timeout \\ 30_000) do
    GenServer.call(pid, {:dimse_request, command_set, data}, timeout)
  end

  @doc """
  Sends an A-RELEASE-RQ and waits for A-RELEASE-RP.
  """
  @spec release(pid(), timeout()) :: :ok | {:error, term()}
  def release(pid, timeout \\ 30_000) do
    GenServer.call(pid, :release, timeout)
  end

  @doc """
  Sends an A-ABORT and terminates the association.
  """
  @spec abort(pid()) :: :ok
  def abort(pid) do
    GenServer.cast(pid, :abort)
  end

  @doc """
  Returns the negotiated contexts for this association.
  """
  @spec negotiated_contexts(pid()) :: %{pos_integer() => {String.t(), String.t()}}
  def negotiated_contexts(pid) do
    GenServer.call(pid, :get_negotiated_contexts)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, %Config{})
    mode = Keyword.get(opts, :mode, :scp)

    state = %State{
      phase: :idle,
      local_ae_title: Keyword.get(opts, :ae_title, config.ae_title),
      handler: Keyword.get(opts, :handler),
      config: config,
      association_id: generate_id(),
      started_at: System.monotonic_time(:millisecond)
    }

    case mode do
      :scp -> init_scp(state, opts)
      :scu -> init_scu(state, opts)
    end
  end

  defp init_scp(state, opts) do
    ranch_ref = Keyword.get(opts, :ranch_ref)
    transport = Keyword.get(opts, :transport, :ranch_tcp)

    if ranch_ref do
      # Cannot call :ranch.handshake in init — it deadlocks because Ranch
      # waits for start_link to return before sending the handshake message.
      # Use handle_continue to defer the handshake.
      Process.put(:ranch_ref, ranch_ref)
      new_state = %{state | transport: transport, phase: :idle}
      {:ok, new_state, {:continue, :handshake}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:handshake, state) do
    ranch_ref = Process.delete(:ranch_ref)
    {:ok, socket} = :ranch.handshake(ranch_ref)
    state.transport.setopts(socket, active: :once, packet: :raw, mode: :binary)

    new_state =
      %{state | socket: socket}
      |> start_artim_timer()

    Telemetry.emit(:association_start, %{system_time: System.system_time()}, %{
      association_id: state.association_id,
      mode: :scp
    })

    {:noreply, new_state}
  end

  defp init_scu(state, opts) do
    host = Keyword.get(opts, :host)
    port = Keyword.get(opts, :port)
    called_ae = Keyword.get(opts, :called_ae)
    calling_ae = Keyword.get(opts, :calling_ae, state.local_ae_title)
    abstract_syntaxes = Keyword.get(opts, :abstract_syntaxes, [])

    transfer_syntaxes =
      Keyword.get(opts, :transfer_syntaxes, MapSet.to_list(@default_transfer_syntaxes))

    timeout = Keyword.get(opts, :timeout, state.config.dimse_timeout)

    case :gen_tcp.connect(
           to_charlist(host),
           port,
           [:binary, active: :once, packet: :raw],
           timeout
         ) do
      {:ok, socket} ->
        new_state = %{
          state
          | socket: socket,
            transport: :gen_tcp,
            local_ae_title: calling_ae,
            remote_ae_title: called_ae,
            phase: :negotiating
        }

        # Build and send A-ASSOCIATE-RQ
        rq =
          build_associate_rq(
            calling_ae,
            called_ae,
            abstract_syntaxes,
            transfer_syntaxes,
            state.config
          )

        send_pdu(new_state, rq)

        Telemetry.emit(:association_start, %{system_time: System.system_time()}, %{
          association_id: state.association_id,
          mode: :scu
        })

        {:ok, new_state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:dimse_request, command_set, data}, from, %{phase: :established} = state) do
    # Find a context for the SOP class
    sop_class = Map.get(command_set, {0x0000, 0x0002})
    context_id = find_context_id(state.negotiated_contexts, sop_class)

    if context_id do
      pdus = Message.fragment(command_set, data, context_id, state.max_pdu_length)
      Enum.each(pdus, &send_pdu(state, &1))
      {:noreply, %{state | pending_request: from}}
    else
      {:reply, {:error, :no_accepted_context}, state}
    end
  end

  def handle_call(:release, from, %{phase: :established} = state) do
    send_pdu(state, %Pdu.ReleaseRq{})
    start_artim_timer(state)
    {:noreply, %{state | phase: :releasing, pending_release: from}}
  end

  def handle_call(:get_negotiated_contexts, _from, state) do
    {:reply, state.negotiated_contexts, state}
  end

  def handle_call(_msg, _from, state), do: {:reply, {:error, :not_established}, state}

  @impl true
  def handle_cast(:abort, state) do
    if state.socket, do: send_pdu(state, %Pdu.Abort{source: 0, reason: 0})
    close_connection(state, :aborted)
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    # Accumulate buffer and process PDUs
    buffer = state.pdu_buffer <> data
    new_state = %{state | bytes_received: state.bytes_received + byte_size(data)}

    case process_buffer(buffer, new_state) do
      {:ok, remaining_buffer, final_state} ->
        reactivate_socket(final_state)
        {:noreply, %{final_state | pdu_buffer: remaining_buffer}}

      {:stop, reason, final_state} ->
        close_connection(final_state, reason)
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    close_connection(state, :tcp_closed)
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    close_connection(state, {:tcp_error, reason})
  end

  def handle_info(:artim_timeout, state) do
    send_pdu(state, %Pdu.Abort{source: 2, reason: 0})
    close_connection(state, :artim_timeout)
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    duration = System.monotonic_time(:millisecond) - state.started_at

    Telemetry.emit(
      :association_stop,
      %{
        duration: duration,
        bytes_received: state.bytes_received,
        bytes_sent: state.bytes_sent
      },
      %{
        association_id: state.association_id,
        reason: reason
      }
    )

    if state.socket do
      close_socket(state)
    end
  end

  # --- Buffer processing ---

  defp process_buffer(buffer, state) do
    case Decoder.decode(buffer) do
      {:ok, pdu, rest} ->
        case handle_pdu(pdu, state) do
          {:ok, new_state} -> process_buffer(rest, new_state)
          {:stop, reason, new_state} -> {:stop, reason, new_state}
        end

      {:incomplete, _} ->
        {:ok, buffer, state}

      {:error, reason} ->
        {:stop, {:decode_error, reason}, state}
    end
  end

  # --- PDU dispatch by state ---

  # SCP Idle: expecting A-ASSOCIATE-RQ
  defp handle_pdu(%Pdu.AssociateRq{} = rq, %{phase: :idle} = state) do
    cancel_artim_timer(state)
    handle_associate_rq(rq, state)
  end

  # SCU Negotiating: expecting A-ASSOCIATE-AC or A-ASSOCIATE-RJ
  defp handle_pdu(%Pdu.AssociateAc{} = ac, %{phase: :negotiating} = state) do
    handle_associate_ac(ac, state)
  end

  defp handle_pdu(%Pdu.AssociateRj{} = rj, %{phase: :negotiating} = state) do
    if state.pending_request do
      # SCU init is waiting — we use the init caller stored elsewhere
    end

    {:stop, {:rejected, rj.result, rj.source, rj.reason}, state}
  end

  # Established: P-DATA-TF
  defp handle_pdu(%Pdu.PDataTf{} = pdu, %{phase: :established} = state) do
    handle_p_data(pdu, state)
  end

  # Release
  defp handle_pdu(%Pdu.ReleaseRq{}, %{phase: :established} = state) do
    send_pdu(state, %Pdu.ReleaseRp{})
    {:stop, :normal, %{state | phase: :closed}}
  end

  defp handle_pdu(%Pdu.ReleaseRp{}, %{phase: :releasing} = state) do
    cancel_artim_timer(state)

    if state.pending_release do
      GenServer.reply(state.pending_release, :ok)
    end

    {:stop, :normal, %{state | phase: :closed, pending_release: nil}}
  end

  # Abort from any state
  defp handle_pdu(%Pdu.Abort{} = abort, state) do
    if state.pending_request do
      GenServer.reply(state.pending_request, {:error, {:aborted, abort.source, abort.reason}})
    end

    if state.pending_release do
      GenServer.reply(state.pending_release, {:error, :aborted})
    end

    {:stop, {:aborted, abort.source, abort.reason},
     %{state | pending_request: nil, pending_release: nil}}
  end

  # Unexpected PDU
  defp handle_pdu(_pdu, state) do
    send_pdu(state, %Pdu.Abort{source: 2, reason: 2})
    {:stop, :unexpected_pdu, state}
  end

  # --- Association negotiation (SCP) ---

  defp handle_associate_rq(rq, state) do
    handler = state.handler
    supported_as = handler_abstract_syntaxes(handler)
    supported_ts = @default_transfer_syntaxes

    {result_contexts, accepted_map} =
      Negotiation.negotiate(rq.presentation_contexts, supported_as, supported_ts)

    if map_size(accepted_map) == 0 do
      # Reject — no acceptable contexts
      send_pdu(state, %Pdu.AssociateRj{result: 1, source: 1, reason: 1})
      {:stop, :no_accepted_contexts, state}
    else
      remote_max_pdu =
        case rq.user_information do
          %Pdu.UserInformation{max_pdu_length: len} when is_integer(len) and len > 0 -> len
          _ -> 16_384
        end

      effective_max_pdu = min(remote_max_pdu, state.config.max_pdu_length)

      ac = %Pdu.AssociateAc{
        protocol_version: 1,
        called_ae_title: rq.called_ae_title,
        calling_ae_title: state.local_ae_title,
        presentation_contexts: result_contexts,
        user_information: %Pdu.UserInformation{
          max_pdu_length: state.config.max_pdu_length,
          implementation_uid: @implementation_uid,
          implementation_version: @implementation_version
        }
      }

      send_pdu(state, ac)

      {:ok,
       %{
         state
         | phase: :established,
           remote_ae_title: rq.calling_ae_title,
           negotiated_contexts: accepted_map,
           max_pdu_length: effective_max_pdu,
           implementation_uid: get_in_user_info(rq, :implementation_uid),
           implementation_version: get_in_user_info(rq, :implementation_version)
       }}
    end
  end

  # --- Association negotiation (SCU) ---

  defp handle_associate_ac(ac, state) do
    accepted =
      for %Pdu.PresentationContext{id: id, result: 0, transfer_syntaxes: [ts | _]} <-
            ac.presentation_contexts,
          into: %{} do
        # We need the abstract syntax from our original proposal — use a lookup
        # For now, store the transfer syntax; the abstract syntax comes from context
        {id, {nil, ts}}
      end

    remote_max_pdu =
      case ac.user_information do
        %Pdu.UserInformation{max_pdu_length: len} when is_integer(len) and len > 0 -> len
        _ -> 16_384
      end

    effective_max_pdu = min(remote_max_pdu, state.config.max_pdu_length)

    {:ok,
     %{
       state
       | phase: :established,
         negotiated_contexts: accepted,
         max_pdu_length: effective_max_pdu,
         implementation_uid: get_in_user_info(ac, :implementation_uid),
         implementation_version: get_in_user_info(ac, :implementation_version)
     }}
  end

  # --- P-DATA handling ---

  defp handle_p_data(%Pdu.PDataTf{pdv_items: items}, state) do
    process_pdv_items(items, state)
  end

  defp process_pdv_items([], state), do: {:ok, state}

  defp process_pdv_items([pdv | rest], state) do
    assembler = state.current_dimse_message || Message.Assembler.new()

    case Message.Assembler.feed(assembler, pdv) do
      {:continue, new_assembler} ->
        process_pdv_items(rest, %{state | current_dimse_message: new_assembler})

      {:complete, message} ->
        new_state = %{state | current_dimse_message: nil}
        handle_dimse_message(message, new_state, rest)

      {:error, reason} ->
        {:stop, {:message_assembly_error, reason}, state}
    end
  end

  defp handle_dimse_message(message, state, remaining_pdvs) do
    command_field = Command.command_field(message.command)

    cond do
      # Response to our SCU request
      Fields.response?(command_field) and state.pending_request != nil ->
        GenServer.reply(state.pending_request, {:ok, message.command, message.data})
        new_state = %{state | pending_request: nil}
        process_pdv_items(remaining_pdvs, new_state)

      # Incoming SCP request
      Fields.request?(command_field) ->
        dispatch_scp_request(message, state, remaining_pdvs)

      true ->
        {:stop, :unexpected_command, state}
    end
  end

  defp dispatch_scp_request(message, state, remaining_pdvs) do
    handler = state.handler
    command_field = Command.command_field(message.command)
    message_id = Command.message_id(message.command) || 0
    start_time = System.monotonic_time(:millisecond)

    Telemetry.emit(:command_start, %{system_time: System.system_time()}, %{
      association_id: state.association_id,
      command_field: command_field,
      message_id: message_id
    })

    {status, response_data} =
      case command_field do
        0x0030 ->
          # C-ECHO-RQ
          case handler.handle_echo(message.command, state) do
            {:ok, status} -> {status, nil}
            {:error, status, _msg} -> {status, nil}
          end

        0x0001 ->
          # C-STORE-RQ
          case handler.handle_store(message.command, message.data, state) do
            {:ok, status} -> {status, nil}
            {:error, status, _msg} -> {status, nil}
          end

        0x0020 ->
          # C-FIND-RQ
          case handler.handle_find(message.command, message.data, state) do
            {:ok, results} -> send_find_results(results, message, state)
            {:error, status, _msg} -> {status, nil}
          end

        _ ->
          # Unsupported command
          {0xC000, nil}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    Telemetry.emit(:command_stop, %{duration: duration}, %{
      association_id: state.association_id,
      command_field: command_field,
      status: status
    })

    # Send response
    response_field = Bitwise.bor(command_field, 0x8000)

    response_command =
      %{
        {0x0000, 0x0002} => Command.affected_sop_class_uid(message.command) || "",
        {0x0000, 0x0100} => response_field,
        {0x0000, 0x0120} => message_id,
        {0x0000, 0x0800} => 0x0101,
        {0x0000, 0x0900} => status
      }
      |> maybe_put_instance_uid(command_field, message.command)

    pdus =
      Message.fragment(response_command, response_data, message.context_id, state.max_pdu_length)

    Enum.each(pdus, &send_pdu(state, &1))

    process_pdv_items(remaining_pdvs, state)
  end

  defp send_find_results(results, message, state) do
    # Send each result with Pending status, then final Success
    Enum.each(results, fn result_data ->
      pending_command = %{
        {0x0000, 0x0002} => Command.affected_sop_class_uid(message.command) || "",
        {0x0000, 0x0100} => Fields.c_find_rsp(),
        {0x0000, 0x0120} => Command.message_id(message.command) || 0,
        {0x0000, 0x0800} => 0x0000,
        {0x0000, 0x0900} => 0xFF00
      }

      pdus =
        Message.fragment(pending_command, result_data, message.context_id, state.max_pdu_length)

      Enum.each(pdus, &send_pdu(state, &1))
    end)

    # Final success (no data set)
    {0x0000, nil}
  end

  # --- Socket I/O ---

  defp send_pdu(state, pdu) do
    iodata = Encoder.encode(pdu)
    byte_count = :erlang.iolist_size(iodata)

    case state.transport do
      :gen_tcp -> :gen_tcp.send(state.socket, iodata)
      transport -> transport.send(state.socket, iodata)
    end

    Telemetry.emit(:pdu_sent, %{byte_size: byte_count}, %{
      association_id: state.association_id,
      pdu_type: pdu.__struct__
    })
  end

  defp reactivate_socket(%{transport: :gen_tcp, socket: socket}) do
    :inet.setopts(socket, active: :once)
  end

  defp reactivate_socket(%{transport: transport, socket: socket}) do
    transport.setopts(socket, active: :once)
  end

  defp close_socket(%{socket: nil}), do: :ok
  defp close_socket(%{transport: :gen_tcp, socket: socket}), do: :gen_tcp.close(socket)
  defp close_socket(%{transport: transport, socket: socket}), do: transport.close(socket)

  defp close_connection(state, reason) do
    if state.pending_request do
      GenServer.reply(state.pending_request, {:error, reason})
    end

    if state.pending_release do
      GenServer.reply(state.pending_release, {:error, reason})
    end

    {:stop, reason, %{state | phase: :closed, pending_request: nil, pending_release: nil}}
  end

  # --- ARTIM timer ---

  defp start_artim_timer(state) do
    timer = Process.send_after(self(), :artim_timeout, state.config.artim_timeout)
    %{state | artim_timer: timer}
  end

  defp cancel_artim_timer(%{artim_timer: nil}), do: :ok
  defp cancel_artim_timer(%{artim_timer: ref}), do: Process.cancel_timer(ref)

  # --- Helpers ---

  defp build_associate_rq(calling_ae, called_ae, abstract_syntaxes, transfer_syntaxes, config) do
    pcs =
      abstract_syntaxes
      |> Enum.with_index(1)
      |> Enum.map(fn {as, idx} ->
        %Pdu.PresentationContext{
          id: idx * 2 - 1,
          abstract_syntax: as,
          transfer_syntaxes: transfer_syntaxes
        }
      end)

    %Pdu.AssociateRq{
      protocol_version: 1,
      called_ae_title: called_ae,
      calling_ae_title: calling_ae,
      presentation_contexts: pcs,
      user_information: %Pdu.UserInformation{
        max_pdu_length: config.max_pdu_length,
        implementation_uid: @implementation_uid,
        implementation_version: @implementation_version
      }
    }
  end

  defp handler_abstract_syntaxes(nil), do: MapSet.new(["1.2.840.10008.1.1"])

  defp handler_abstract_syntaxes(handler) do
    if function_exported?(handler, :supported_abstract_syntaxes, 0) do
      handler.supported_abstract_syntaxes() |> MapSet.new()
    else
      MapSet.new(["1.2.840.10008.1.1"])
    end
  end

  defp find_context_id(contexts, sop_class) do
    Enum.find_value(contexts, fn
      {id, {^sop_class, _ts}} -> id
      {id, {nil, _ts}} -> id
      _ -> nil
    end)
  end

  defp get_in_user_info(%{user_information: %Pdu.UserInformation{} = ui}, field) do
    Map.get(ui, field)
  end

  defp get_in_user_info(_, _), do: nil

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # C-STORE-RSP must echo back the AffectedSOPInstanceUID (PS3.7 Table 9.1-1)
  defp maybe_put_instance_uid(cmd, 0x0001, request_command) do
    case Map.get(request_command, {0x0000, 0x1000}) do
      nil -> cmd
      uid -> Map.put(cmd, {0x0000, 0x1000}, uid)
    end
  end

  defp maybe_put_instance_uid(cmd, _command_field, _request_command), do: cmd
end
