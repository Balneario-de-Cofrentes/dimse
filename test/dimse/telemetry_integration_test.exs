defmodule Dimse.TelemetryIntegrationTest do
  use ExUnit.Case

  @moduletag :telemetry_integration

  @verification_uid "1.2.840.10008.1.1"
  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"
  @study_root_get "1.2.840.10008.5.1.4.1.2.2.3"

  # Collects telemetry events matching the given event names into the test process mailbox.
  defp attach_telemetry(handler_id, event_names) do
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      event_names,
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )
  end

  defp detach_telemetry(handler_id) do
    :telemetry.detach(handler_id)
  end

  defp wait_for_established(assoc, timeout \\ 2_000) do
    contexts = Dimse.Association.negotiated_contexts(assoc)

    assert map_size(contexts) > 0,
           "Association was not established within #{timeout}ms"

    :ok
  end

  # --- Echo roundtrip: association + negotiation + command + handler events ---

  describe "echo roundtrip telemetry" do
    test "fires association, negotiation, command, and handler events" do
      handler_id = "echo-telemetry-#{inspect(make_ref())}"

      attach_telemetry(handler_id, [
        [:dimse, :association_start],
        [:dimse, :association_stop],
        [:dimse, :negotiation, :start],
        [:dimse, :negotiation, :stop],
        [:dimse, :command_start],
        [:dimse, :command_stop],
        [:dimse, :handler, :start],
        [:dimse, :handler, :stop],
        [:dimse, :pdu_sent]
      ])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TELEM_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@verification_uid]
        )

      wait_for_established(assoc)
      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)
      # Small delay for SCP-side terminate events
      Process.sleep(50)
      Dimse.stop_listener(ref)

      detach_telemetry(handler_id)

      # SCU association start
      assert_received {:telemetry, [:dimse, :association_start], %{system_time: _},
                       %{association_id: _, mode: :scu}}

      # SCP association start
      assert_received {:telemetry, [:dimse, :association_start], %{system_time: _},
                       %{association_id: _, mode: :scp}}

      # SCU negotiation start
      assert_received {:telemetry, [:dimse, :negotiation, :start], %{system_time: _},
                       %{
                         mode: :scu,
                         calling_ae: "TELEM_SCU",
                         called_ae: "DIMSE",
                         proposed_contexts_count: 1
                       }}

      # SCP negotiation start
      assert_received {:telemetry, [:dimse, :negotiation, :start], %{system_time: _},
                       %{
                         mode: :scp,
                         calling_ae: "TELEM_SCU",
                         called_ae: "DIMSE",
                         proposed_contexts_count: _
                       }}

      # SCU negotiation stop (accepted)
      assert_received {:telemetry, [:dimse, :negotiation, :stop], _,
                       %{mode: :scu, result: :accepted, accepted_contexts_count: 1}}

      # SCP negotiation stop (accepted)
      assert_received {:telemetry, [:dimse, :negotiation, :stop], _,
                       %{mode: :scp, result: :accepted, accepted_contexts_count: 1}}

      # Command events (SCP side)
      assert_received {:telemetry, [:dimse, :command_start], %{system_time: _},
                       %{command_field: 0x0030, message_id: _}}

      assert_received {:telemetry, [:dimse, :command_stop], %{duration: _},
                       %{command_field: 0x0030, status: 0x0000}}

      # Handler events (SCP side)
      assert_received {:telemetry, [:dimse, :handler, :start], %{system_time: _},
                       %{callback: :handle_echo, command_field: 0x0030}}

      assert_received {:telemetry, [:dimse, :handler, :stop], %{duration: _},
                       %{callback: :handle_echo, status: 0x0000}}

      # PDU sent events should be present
      assert_received {:telemetry, [:dimse, :pdu_sent], %{byte_size: _}, %{pdu_type: _}}
    end
  end

  # --- Store roundtrip: handler events for C-STORE ---

  describe "store roundtrip telemetry" do
    test "fires handler events for C-STORE" do
      handler_id = "store-telemetry-#{inspect(make_ref())}"

      attach_telemetry(handler_id, [
        [:dimse, :handler, :start],
        [:dimse, :handler, :stop]
      ])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: TelemetryTestStoreHandler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TELEM_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@ct_image_storage]
        )

      wait_for_established(assoc)

      data = :crypto.strong_rand_bytes(128)
      assert :ok = Dimse.store(assoc, @ct_image_storage, "1.2.3.4.5", data, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)

      Dimse.stop_listener(ref)
      detach_telemetry(handler_id)

      assert_received {:telemetry, [:dimse, :handler, :start], %{system_time: _},
                       %{callback: :handle_store, command_field: 0x0001}}

      assert_received {:telemetry, [:dimse, :handler, :stop], %{duration: _},
                       %{callback: :handle_store, status: 0x0000}}
    end
  end

  # --- TLS handshake event ---

  describe "TLS handshake telemetry" do
    @tag :tls
    test "fires tls handshake event on TLS connection" do
      handler_id = "tls-handshake-telemetry-#{inspect(make_ref())}"

      attach_telemetry(handler_id, [
        [:dimse, :tls, :handshake]
      ])

      certs = Dimse.Test.TlsHelpers.generate_tls_certs()
      on_exit(fn -> File.rm_rf!(certs.dir) end)

      {:ok, ref} =
        Dimse.start_listener(
          port: 0,
          handler: Dimse.Scp.Echo,
          tls: [certfile: certs.server_certfile, keyfile: certs.server_keyfile]
        )

      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TLS_SCU",
          called_ae: "TLS_SCP",
          abstract_syntaxes: [@verification_uid],
          tls: [cacertfile: certs.cacertfile, verify: :verify_peer]
        )

      wait_for_established(assoc)
      assert :ok = Dimse.echo(assoc, timeout: 5_000)
      assert :ok = Dimse.release(assoc, 5_000)

      Dimse.stop_listener(ref)
      detach_telemetry(handler_id)

      # SCU-side TLS handshake event
      assert_received {:telemetry, [:dimse, :tls, :handshake], %{},
                       %{association_id: _, protocol_version: proto, cipher_suite: _}}
                      when not is_nil(proto)
    end
  end

  # --- C-GET sub-operation events ---

  describe "C-GET sub-operation telemetry" do
    test "fires sub_operation start, progress, and stop events" do
      handler_id = "get-subop-telemetry-#{inspect(make_ref())}"

      attach_telemetry(handler_id, [
        [:dimse, :sub_operation, :start],
        [:dimse, :sub_operation, :progress],
        [:dimse, :sub_operation, :stop],
        [:dimse, :handler, :start],
        [:dimse, :handler, :stop]
      ])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: TelemetryTestGetHandler)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TELEM_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@study_root_get, @ct_image_storage],
          role_selections: [
            %Dimse.Pdu.RoleSelection{
              sop_class_uid: @ct_image_storage,
              scu_role: true,
              scp_role: true
            }
          ]
        )

      wait_for_established(assoc)

      assert {:ok, _results} = Dimse.get(assoc, :study, <<>>, timeout: 10_000)
      assert :ok = Dimse.release(assoc, 5_000)

      Dimse.stop_listener(ref)
      detach_telemetry(handler_id)

      # Handler events for handle_get
      assert_received {:telemetry, [:dimse, :handler, :start], _,
                       %{callback: :handle_get, command_field: 0x0010}}

      assert_received {:telemetry, [:dimse, :handler, :stop], _, %{callback: :handle_get}}

      # Sub-operation start
      assert_received {:telemetry, [:dimse, :sub_operation, :start], %{system_time: _},
                       %{type: :c_get, total_instances: 2}}

      # Sub-operation progress (at least one)
      assert_received {:telemetry, [:dimse, :sub_operation, :progress], %{},
                       %{type: :c_get, completed: _, failed: _, remaining: _}}

      # Sub-operation stop
      assert_received {:telemetry, [:dimse, :sub_operation, :stop], %{},
                       %{type: :c_get, completed: _, failed: _, warning: _}}
    end
  end

  # --- Failed negotiation fires negotiation stop with result: :rejected ---

  describe "failed negotiation telemetry" do
    test "negotiation stop fires with result: :rejected" do
      handler_id = "rejected-negotiation-telemetry-#{inspect(make_ref())}"

      attach_telemetry(handler_id, [
        [:dimse, :negotiation, :start],
        [:dimse, :negotiation, :stop]
      ])

      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      # Request a SOP class the SCP does not support -> rejection
      result =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TELEM_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@ct_image_storage],
          timeout: 2_000
        )

      assert {:error, {:rejected, _, _, _}} = result

      # Small delay for SCP-side events
      Process.sleep(50)
      Dimse.stop_listener(ref)
      detach_telemetry(handler_id)

      # SCU negotiation start
      assert_received {:telemetry, [:dimse, :negotiation, :start], _,
                       %{mode: :scu, proposed_contexts_count: 1}}

      # SCP negotiation start
      assert_received {:telemetry, [:dimse, :negotiation, :start], _, %{mode: :scp}}

      # SCP negotiation stop with rejection
      assert_received {:telemetry, [:dimse, :negotiation, :stop], _,
                       %{mode: :scp, result: :rejected, accepted_contexts_count: 0}}

      # SCU negotiation stop with rejection
      assert_received {:telemetry, [:dimse, :negotiation, :stop], _,
                       %{mode: :scu, result: :rejected, rejected_contexts_count: 1}}
    end
  end
end

# --- Test handler modules for telemetry tests ---

defmodule TelemetryTestStoreHandler do
  @behaviour Dimse.Handler

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"

  @impl true
  def supported_abstract_syntaxes, do: [@ct_image_storage]

  @impl true
  def handle_echo(_command, _state), do: {:ok, 0x0000}

  @impl true
  def handle_store(_command, _data, _state), do: {:ok, 0x0000}

  @impl true
  def handle_find(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_move(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_get(_command, _query, _state), do: {:ok, []}
end

defmodule TelemetryTestGetHandler do
  @behaviour Dimse.Handler

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"
  @study_root_get "1.2.840.10008.5.1.4.1.2.2.3"

  @impl true
  def supported_abstract_syntaxes, do: [@study_root_get, @ct_image_storage]

  @impl true
  def handle_echo(_command, _state), do: {:ok, 0x0000}

  @impl true
  def handle_store(_command, _data, _state), do: {:ok, 0x0000}

  @impl true
  def handle_find(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_move(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_get(_command, _query, _state) do
    # Return 2 instances for sub-operation testing
    instances = [
      {@ct_image_storage, "1.2.3.4.5.1", <<1, 2, 3, 4>>},
      {@ct_image_storage, "1.2.3.4.5.2", <<5, 6, 7, 8>>}
    ]

    {:ok, instances}
  end
end
