defmodule Dimse.Pdu.Decoder do
  @moduledoc """
  Decodes DICOM PDU binaries into `Dimse.Pdu` structs.

  Implements the binary wire format defined in PS3.8 Section 9.3. Each PDU type
  has a fixed header (1 byte type + 1 byte reserved + 4 byte length) followed by
  a type-specific payload.

  Uses Elixir binary pattern matching for direct translation of the PDU format
  tables in the DICOM standard.

  ## Usage

      {:ok, pdu, rest} = Dimse.Pdu.Decoder.decode(binary)
      {:incomplete, binary} = Dimse.Pdu.Decoder.decode(partial_binary)
      {:error, reason} = Dimse.Pdu.Decoder.decode(invalid_binary)

  ## PDU Header Format

      <<type::8, 0x00::8, length::32-big, payload::binary-size(length)>>

  The decoder handles incomplete reads (when not enough bytes have arrived from
  the TCP socket) by returning `{:incomplete, buffer}` so the caller can
  accumulate more data before retrying.
  """

  @doc """
  Decodes the next PDU from the given binary.

  Returns:
    - `{:ok, pdu_struct, rest}` — successfully decoded PDU with remaining bytes
    - `{:incomplete, binary}` — not enough data, caller should buffer and retry
    - `{:error, reason}` — malformed or unknown PDU type
  """
  @spec decode(binary()) ::
          {:ok, struct(), binary()} | {:incomplete, binary()} | {:error, term()}
  def decode(_binary) do
    {:error, :not_implemented}
  end
end
