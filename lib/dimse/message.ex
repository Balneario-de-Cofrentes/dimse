defmodule Dimse.Message do
  @moduledoc """
  DIMSE message assembly from P-DATA-TF fragments.

  A DIMSE message consists of a command set (always one P-DATA fragment with
  the command flag set) followed by zero or one data sets (one or more P-DATA
  fragments with the command flag cleared). Messages may span multiple P-DATA-TF
  PDUs when the data exceeds the negotiated max PDU length.

  ## Fragment Assembly Rules (PS3.7 Section 6.3.1)

  1. A command set is carried in PDVs with `is_command: true`
  2. The last command fragment has `is_last: true`
  3. If `CommandDataSetType != 0x0101`, a data set follows
  4. Data set fragments have `is_command: false`
  5. The last data fragment has `is_last: true`
  6. All fragments for a message use the same presentation context ID
  """

  alias Dimse.Pdu

  @type t :: %__MODULE__{
          context_id: pos_integer() | nil,
          command: map() | nil,
          data: binary() | nil
        }

  defstruct [:context_id, :command, :data]

  defmodule Assembler do
    @moduledoc """
    Stateful accumulator for reassembling DIMSE messages from PDV fragments.

    ## Phases

    1. `:command` — accumulating command set fragments
    2. `:data` — accumulating data set fragments (if CommandDataSetType != 0x0101)
    3. `:complete` — message fully assembled
    """

    @type phase :: :command | :data | :complete

    @type t :: %__MODULE__{
            phase: phase(),
            context_id: pos_integer() | nil,
            command_buffer: iodata(),
            data_buffer: iodata(),
            command: map() | nil
          }

    defstruct phase: :command,
              context_id: nil,
              command_buffer: [],
              data_buffer: [],
              command: nil

    @doc """
    Creates a new assembler.
    """
    @spec new() :: t()
    def new, do: %__MODULE__{}

    @doc """
    Feeds a PDV item into the assembler.

    Returns:
    - `{:continue, assembler}` — more fragments needed
    - `{:complete, message}` — message fully assembled
    - `{:error, reason}` — protocol error
    """
    @spec feed(t(), Pdu.PresentationDataValue.t()) ::
            {:continue, t()} | {:complete, Dimse.Message.t()} | {:error, term()}
    def feed(
          %__MODULE__{phase: :command} = asm,
          %Pdu.PresentationDataValue{
            is_command: true
          } = pdv
        ) do
      asm = %{asm | context_id: asm.context_id || pdv.context_id}
      new_buffer = [asm.command_buffer | [pdv.data]]

      if pdv.is_last do
        # Command complete — decode it
        command_binary = IO.iodata_to_binary(new_buffer)

        case Dimse.Command.decode(command_binary) do
          {:ok, command} ->
            if Dimse.Command.no_data_set?(command) do
              {:complete,
               %Dimse.Message{
                 context_id: asm.context_id,
                 command: command,
                 data: nil
               }}
            else
              {:continue, %{asm | phase: :data, command_buffer: [], command: command}}
            end

          {:error, reason} ->
            {:error, {:command_decode_failed, reason}}
        end
      else
        {:continue, %{asm | command_buffer: new_buffer}}
      end
    end

    def feed(
          %__MODULE__{phase: :data} = asm,
          %Pdu.PresentationDataValue{
            is_command: false
          } = pdv
        ) do
      new_buffer = [asm.data_buffer | [pdv.data]]

      if pdv.is_last do
        {:complete,
         %Dimse.Message{
           context_id: asm.context_id,
           command: asm.command,
           data: IO.iodata_to_binary(new_buffer)
         }}
      else
        {:continue, %{asm | data_buffer: new_buffer}}
      end
    end

    def feed(_asm, _pdv), do: {:error, :unexpected_pdv}
  end

  @doc """
  Fragments a DIMSE message into P-DATA-TF PDUs respecting max PDU length.

  Returns a list of `Dimse.Pdu.PDataTf` structs ready for encoding.
  """
  @spec fragment(map(), binary() | nil, pos_integer(), pos_integer()) :: [Pdu.PDataTf.t()]
  def fragment(command_set, data, context_id, max_pdu_length) do
    {:ok, command_binary} = Dimse.Command.encode(command_set)

    # PDU overhead: 6 (PDU header) + 4 (PDV length) + 2 (context_id + flags) = 12
    max_pdv_data = max_pdu_length - 12

    command_pdus = fragment_pdvs(command_binary, context_id, true, max_pdv_data)
    data_pdus = if data, do: fragment_pdvs(data, context_id, false, max_pdv_data), else: []

    Enum.map(command_pdus ++ data_pdus, fn pdvs ->
      %Pdu.PDataTf{pdv_items: pdvs}
    end)
  end

  defp fragment_pdvs(binary, context_id, is_command, max_pdv_data) do
    chunks = chunk_binary(binary, max_pdv_data)
    last_idx = length(chunks) - 1

    chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      [
        %Pdu.PresentationDataValue{
          context_id: context_id,
          is_command: is_command,
          is_last: idx == last_idx,
          data: chunk
        }
      ]
    end)
  end

  defp chunk_binary(<<>>, _max), do: [<<>>]

  defp chunk_binary(binary, max) when byte_size(binary) <= max, do: [binary]

  defp chunk_binary(binary, max) do
    <<chunk::binary-size(max), rest::binary>> = binary
    [chunk | chunk_binary(rest, max)]
  end
end
