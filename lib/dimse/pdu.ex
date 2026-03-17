defmodule Dimse.Pdu do
  @moduledoc """
  DICOM Upper Layer PDU type definitions.

  Defines structs for all 7 PDU types specified in DICOM PS3.8 Section 9.3,
  plus their sub-item types used in association negotiation.

  ## PDU Types

  | Type | Hex  | Struct                    | Direction |
  |------|------|---------------------------|-----------|
  | 1    | 0x01 | `AssociateRq`             | SCU → SCP |
  | 2    | 0x02 | `AssociateAc`             | SCP → SCU |
  | 3    | 0x03 | `AssociateRj`             | SCP → SCU |
  | 4    | 0x04 | `PDataTf`                 | Both      |
  | 5    | 0x05 | `ReleaseRq`               | Both      |
  | 6    | 0x06 | `ReleaseRp`               | Both      |
  | 7    | 0x07 | `Abort`                   | Both      |

  ## Sub-Items (inside A-ASSOCIATE-RQ/AC)

  - `PresentationContext` — proposed or accepted abstract syntax + transfer syntaxes
  - `AbstractSyntax` — SOP Class UID
  - `TransferSyntax` — Transfer Syntax UID
  - `UserInformation` — max PDU length, implementation UID/version, extended negotiation

  ## Wire Format

  All PDUs share a common header: 1 byte type, 1 byte reserved (0x00),
  4 bytes length (big-endian uint32). The length field does not include
  the 6-byte header itself.

  See PS3.8 Section 9.3 for complete wire format tables.
  """

  defmodule AssociateRq do
    @moduledoc "A-ASSOCIATE-RQ PDU (type 0x01). PS3.8 Section 9.3.2."
    defstruct [
      :protocol_version,
      :called_ae_title,
      :calling_ae_title,
      :application_context,
      :presentation_contexts,
      :user_information
    ]
  end

  defmodule AssociateAc do
    @moduledoc "A-ASSOCIATE-AC PDU (type 0x02). PS3.8 Section 9.3.3."
    defstruct [
      :protocol_version,
      :called_ae_title,
      :calling_ae_title,
      :application_context,
      :presentation_contexts,
      :user_information
    ]
  end

  defmodule AssociateRj do
    @moduledoc "A-ASSOCIATE-RJ PDU (type 0x03). PS3.8 Section 9.3.4."
    defstruct [:result, :source, :reason]
  end

  defmodule PDataTf do
    @moduledoc "P-DATA-TF PDU (type 0x04). PS3.8 Section 9.3.5."
    defstruct [:pdv_items]
  end

  defmodule PresentationDataValue do
    @moduledoc "Presentation Data Value item within a P-DATA-TF PDU."
    defstruct [:context_id, :is_command, :is_last, :data]
  end

  defmodule ReleaseRq do
    @moduledoc "A-RELEASE-RQ PDU (type 0x05). PS3.8 Section 9.3.6."
    defstruct []
  end

  defmodule ReleaseRp do
    @moduledoc "A-RELEASE-RP PDU (type 0x06). PS3.8 Section 9.3.7."
    defstruct []
  end

  defmodule Abort do
    @moduledoc "A-ABORT PDU (type 0x07). PS3.8 Section 9.3.8."
    defstruct [:source, :reason]
  end

  defmodule PresentationContext do
    @moduledoc "Presentation Context item used in A-ASSOCIATE-RQ/AC."
    defstruct [:id, :result, :abstract_syntax, :transfer_syntaxes]
  end

  defmodule UserInformation do
    @moduledoc "User Information item used in A-ASSOCIATE-RQ/AC. PS3.8 Section 9.3.2.3."
    defstruct [
      :max_pdu_length,
      :implementation_uid,
      :implementation_version,
      :extended_negotiation
    ]
  end
end
