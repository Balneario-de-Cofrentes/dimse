defmodule Dimse.Pdu.Encoder do
  @moduledoc """
  Encodes `Dimse.Pdu` structs into binary iodata for transmission.

  Produces iodata (not flat binaries) to avoid unnecessary copying. The caller
  can pass the result directly to `:gen_tcp.send/2` which accepts iodata.

  Implements the wire format defined in PS3.8 Section 9.3.

  ## Usage

      iodata = Dimse.Pdu.Encoder.encode(%Dimse.Pdu.AssociateRq{...})
      :ok = :gen_tcp.send(socket, iodata)
  """

  @doc """
  Encodes a PDU struct into iodata.

  Returns iodata suitable for sending over a TCP socket.
  """
  @spec encode(struct()) :: iodata()
  def encode(_pdu) do
    raise "not implemented"
  end
end
