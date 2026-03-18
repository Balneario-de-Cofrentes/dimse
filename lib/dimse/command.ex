defmodule Dimse.Command do
  @moduledoc """
  DIMSE command set encoding and decoding.

  Command sets are the control headers of DIMSE messages, always encoded in
  Implicit VR Little Endian regardless of the negotiated transfer syntax
  (PS3.7 Section 6.3.1). All elements belong to group 0000.

  ## Wire Format (Implicit VR Little Endian)

  Each data element: `<<group::16-little, element::16-little, length::32-little, value::binary>>`

  No VR field — the VR is determined from the tag via the DICOM dictionary.

  ## Command Set Elements (PS3.7 Section 6.3)

  | Tag          | Name                      | VR | Description |
  |--------------|---------------------------|----|-------------|
  | (0000,0000)  | CommandGroupLength        | UL | Byte count of remaining command |
  | (0000,0002)  | AffectedSOPClassUID       | UI | SOP Class being operated on |
  | (0000,0100)  | CommandField              | US | Which DIMSE operation |
  | (0000,0110)  | MessageID                 | US | Unique ID for request/response pairing |
  | (0000,0120)  | MessageIDBeingRespondedTo | US | Original request's MessageID |
  | (0000,0800)  | CommandDataSetType        | US | 0x0101 = no data set follows |
  | (0000,0900)  | Status                    | US | Operation result code |

  See `Dimse.Command.Fields` for command field constants and
  `Dimse.Command.Status` for status code definitions.
  """

  # Tag -> VR mapping for group 0000 command elements (PS3.7 Table E.1-1)
  @tag_vr %{
    {0x0000, 0x0000} => :UL,
    {0x0000, 0x0002} => :UI,
    {0x0000, 0x0003} => :UI,
    {0x0000, 0x0100} => :US,
    {0x0000, 0x0110} => :US,
    {0x0000, 0x0120} => :US,
    {0x0000, 0x0200} => :AE,
    {0x0000, 0x0300} => :AE,
    {0x0000, 0x0600} => :AE,
    {0x0000, 0x0700} => :US,
    {0x0000, 0x0800} => :US,
    {0x0000, 0x0900} => :US,
    {0x0000, 0x0901} => :AT,
    {0x0000, 0x0902} => :LO,
    {0x0000, 0x0903} => :US,
    {0x0000, 0x1000} => :UI,
    {0x0000, 0x1001} => :UI,
    {0x0000, 0x1002} => :US,
    {0x0000, 0x1005} => :AT,
    {0x0000, 0x1008} => :US,
    {0x0000, 0x1020} => :US,
    {0x0000, 0x1021} => :US,
    {0x0000, 0x1022} => :US,
    {0x0000, 0x1023} => :US,
    {0x0000, 0x1031} => :US
  }

  @no_data_set 0x0101

  @doc """
  Encodes a command set map into Implicit VR Little Endian binary.

  The map keys are DICOM tags `{group, element}` and values are the
  raw Elixir values to encode. The CommandGroupLength (0000,0000) is
  computed automatically and should not be included in the input map.

  ## Example

      {:ok, binary} = Dimse.Command.encode(%{
        {0x0000, 0x0002} => "1.2.840.10008.1.1",
        {0x0000, 0x0100} => 0x0030,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0101
      })
  """
  @spec encode(map()) :: {:ok, binary()} | {:error, term()}
  def encode(command_set) when is_map(command_set) do
    # Encode all elements except CommandGroupLength, sorted by tag
    elements_binary =
      command_set
      |> Map.delete({0x0000, 0x0000})
      |> Enum.sort()
      |> Enum.map(fn {tag, value} -> encode_element(tag, value) end)
      |> IO.iodata_to_binary()

    # Prepend CommandGroupLength
    group_length_element = encode_element({0x0000, 0x0000}, byte_size(elements_binary))

    {:ok, IO.iodata_to_binary([group_length_element, elements_binary])}
  end

  @doc """
  Decodes an Implicit VR Little Endian binary into a command set map.

  Returns `{:ok, map}` where keys are `{group, element}` tuples and
  values are decoded Elixir values.
  """
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(binary) when is_binary(binary) do
    case decode_elements(binary, []) do
      {:ok, elements} -> {:ok, Map.new(elements)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Returns true if the command set indicates no data set follows.
  """
  @spec no_data_set?(map()) :: boolean()
  def no_data_set?(command_set) do
    Map.get(command_set, {0x0000, 0x0800}) == @no_data_set
  end

  @doc """
  Returns the command field value from a command set.
  """
  @spec command_field(map()) :: integer() | nil
  def command_field(command_set) do
    Map.get(command_set, {0x0000, 0x0100})
  end

  @doc """
  Returns the message ID from a command set.
  """
  @spec message_id(map()) :: integer() | nil
  def message_id(command_set) do
    Map.get(command_set, {0x0000, 0x0110})
  end

  @doc """
  Returns the status from a command set.
  """
  @spec status(map()) :: integer() | nil
  def status(command_set) do
    Map.get(command_set, {0x0000, 0x0900})
  end

  @doc """
  Returns the Affected SOP Class UID from a command set.
  """
  @spec affected_sop_class_uid(map()) :: String.t() | nil
  def affected_sop_class_uid(command_set) do
    Map.get(command_set, {0x0000, 0x0002})
  end

  ## Encoding

  defp encode_element(tag, value) do
    {group, element} = tag
    vr = Map.get(@tag_vr, tag, :UN)
    encoded_value = encode_value(value, vr)
    padded = pad_to_even(encoded_value, vr)

    [
      <<group::16-little, element::16-little, byte_size(padded)::32-little>>,
      padded
    ]
  end

  defp encode_value(value, :US) when is_integer(value), do: <<value::16-little>>
  defp encode_value(value, :UL) when is_integer(value), do: <<value::32-little>>
  defp encode_value(value, :SL) when is_integer(value), do: <<value::32-little-signed>>
  defp encode_value(value, :UI) when is_binary(value), do: value
  defp encode_value(value, :AE) when is_binary(value), do: value
  defp encode_value(value, :LO) when is_binary(value), do: value

  defp encode_value({g, e}, :AT),
    do: <<g::16-little, e::16-little>>

  defp encode_value(values, :AT) when is_list(values) do
    values
    |> Enum.map(fn
      {g, e} -> <<g::16-little, e::16-little>>
    end)
    |> IO.iodata_to_binary()
  end

  defp encode_value(value, _vr) when is_binary(value), do: value

  defp pad_to_even(binary, _vr) when rem(byte_size(binary), 2) == 0, do: binary

  defp pad_to_even(binary, :UI), do: <<binary::binary, 0x00>>
  defp pad_to_even(binary, _vr), do: <<binary::binary, 0x20>>

  ## Decoding

  defp decode_elements(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_elements(
         <<group::16-little, element::16-little, length::32-little, value::binary-size(length),
           rest::binary>>,
         acc
       ) do
    tag = {group, element}
    vr = Map.get(@tag_vr, tag, :UN)
    decoded = decode_value(value, vr)
    decode_elements(rest, [{tag, decoded} | acc])
  end

  defp decode_elements(_, _acc), do: {:error, :malformed_command_set}

  defp decode_value(<<value::16-little>>, :US), do: value
  defp decode_value(<<value::32-little>>, :UL), do: value
  defp decode_value(<<value::32-little-signed>>, :SL), do: value

  defp decode_value(value, :AT) when rem(byte_size(value), 4) == 0 do
    for <<g::16-little, e::16-little <- value>>, do: {g, e}
  end

  defp decode_value(value, :UI), do: String.trim_trailing(value, <<0x00>>)
  defp decode_value(value, :AE), do: String.trim(value)
  defp decode_value(value, :LO), do: String.trim_trailing(value)
  defp decode_value(value, _vr), do: value
end
