defmodule Dimse.Command do
  @moduledoc """
  DIMSE command set encoding and decoding.

  Command sets are the control headers of DIMSE messages, always encoded in
  Implicit VR Little Endian regardless of the negotiated transfer syntax
  (PS3.7 Section 6.3.1). All elements belong to group 0000.

  Uses the `dicom` library for Implicit VR Little Endian encoding/decoding
  of group 0000 data elements.

  ## Command Set Elements (PS3.7 Section 6.3)

  Key fields common to all commands:

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

  @doc """
  Encodes a command set map into Implicit VR Little Endian binary.

  The map keys are DICOM tags `{group, element}` and values are the
  raw values to encode.
  """
  @spec encode(map()) :: {:ok, binary()} | {:error, term()}
  def encode(_command_set) do
    {:error, :not_implemented}
  end

  @doc """
  Decodes an Implicit VR Little Endian binary into a command set map.
  """
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(_binary) do
    {:error, :not_implemented}
  end
end
