defmodule Dimse.Message do
  @moduledoc """
  DIMSE message assembly from P-DATA-TF fragments.

  A DIMSE message consists of a command set (always one P-DATA fragment with
  the command flag set) followed by zero or one data sets (one or more P-DATA
  fragments with the command flag cleared). Messages may span multiple P-DATA-TF
  PDUs when the data exceeds the negotiated max PDU length.

  This module handles the reassembly of fragmented P-DATA into complete DIMSE
  messages ready for dispatch to service class handlers.

  ## Fragment Assembly Rules (PS3.7 Section 6.3.1)

  1. A command set is carried in PDVs with `is_command: true`
  2. The last command fragment has `is_last: true`
  3. If `CommandDataSetType != 0x0101`, a data set follows
  4. Data set fragments have `is_command: false`
  5. The last data fragment has `is_last: true`
  6. All fragments for a message use the same presentation context ID

  ## Struct

  A complete `Dimse.Message` contains:
  - `:context_id` — presentation context ID
  - `:command` — decoded command set (map)
  - `:data` — data set binary (or nil if no data set)
  """

  @type t :: %__MODULE__{
          context_id: pos_integer() | nil,
          command: map() | nil,
          data: binary() | nil
        }

  defstruct [:context_id, :command, :data]
end
