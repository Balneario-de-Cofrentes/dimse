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
  - `RoleSelection` — SCU/SCP role negotiation per SOP class (PS3.7 D.3.3.4)
  - `SopClassExtendedNegotiation` — service-class-specific info per SOP class (PS3.7 D.3.3.5)
  - `SopClassCommonExtendedNegotiation` — service class + related SOP classes (PS3.7 D.3.3.6)
  - `UserIdentity` — SCU authentication credentials in A-ASSOCIATE-RQ (PS3.7 D.3.3.7)
  - `UserIdentityAc` — SCP server response in A-ASSOCIATE-AC (PS3.7 D.3.3.8)

  ## Wire Format

  All PDUs share a common header: 1 byte type, 1 byte reserved (0x00),
  4 bytes length (big-endian uint32). The length field does not include
  the 6-byte header itself.

  See PS3.8 Section 9.3 for complete wire format tables.
  """

  defmodule AssociateRq do
    @moduledoc "A-ASSOCIATE-RQ PDU (type 0x01). PS3.8 Section 9.3.2."

    @type t :: %__MODULE__{
            protocol_version: pos_integer() | nil,
            called_ae_title: String.t() | nil,
            calling_ae_title: String.t() | nil,
            application_context: String.t() | nil,
            presentation_contexts: [Dimse.Pdu.PresentationContext.t()] | nil,
            user_information: Dimse.Pdu.UserInformation.t() | nil
          }

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

    @type t :: %__MODULE__{
            protocol_version: pos_integer() | nil,
            called_ae_title: String.t() | nil,
            calling_ae_title: String.t() | nil,
            application_context: String.t() | nil,
            presentation_contexts: [Dimse.Pdu.PresentationContext.t()] | nil,
            user_information: Dimse.Pdu.UserInformation.t() | nil
          }

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

    @type t :: %__MODULE__{
            result: non_neg_integer() | nil,
            source: non_neg_integer() | nil,
            reason: non_neg_integer() | nil
          }

    defstruct [:result, :source, :reason]
  end

  defmodule PDataTf do
    @moduledoc "P-DATA-TF PDU (type 0x04). PS3.8 Section 9.3.5."

    @type t :: %__MODULE__{
            pdv_items: [Dimse.Pdu.PresentationDataValue.t()] | nil
          }

    defstruct [:pdv_items]
  end

  defmodule PresentationDataValue do
    @moduledoc "Presentation Data Value item within a P-DATA-TF PDU."

    @type t :: %__MODULE__{
            context_id: pos_integer() | nil,
            is_command: boolean() | nil,
            is_last: boolean() | nil,
            data: binary() | nil
          }

    defstruct [:context_id, :is_command, :is_last, :data]
  end

  defmodule ReleaseRq do
    @moduledoc "A-RELEASE-RQ PDU (type 0x05). PS3.8 Section 9.3.6."
    @type t :: %__MODULE__{}
    defstruct []
  end

  defmodule ReleaseRp do
    @moduledoc "A-RELEASE-RP PDU (type 0x06). PS3.8 Section 9.3.7."
    @type t :: %__MODULE__{}
    defstruct []
  end

  defmodule Abort do
    @moduledoc "A-ABORT PDU (type 0x07). PS3.8 Section 9.3.8."

    @type t :: %__MODULE__{
            source: non_neg_integer() | nil,
            reason: non_neg_integer() | nil
          }

    defstruct [:source, :reason]
  end

  defmodule PresentationContext do
    @moduledoc "Presentation Context item used in A-ASSOCIATE-RQ/AC."

    @type t :: %__MODULE__{
            id: pos_integer() | nil,
            result: non_neg_integer() | nil,
            abstract_syntax: String.t() | nil,
            transfer_syntaxes: [String.t()] | nil
          }

    defstruct [:id, :result, :abstract_syntax, :transfer_syntaxes]
  end

  defmodule UserInformation do
    @moduledoc """
    User Information item used in A-ASSOCIATE-RQ/AC. PS3.8 Section 9.3.2.3.

    ## Extended Negotiation Sub-Items (PS3.7 Annex D)

    | Type | Hex  | Struct                              | Notes                       |
    |------|------|-------------------------------------|-----------------------------|
    | –    | 0x51 | (inline) max_pdu_length             | PS3.7 D.3.3.1               |
    | –    | 0x52 | (inline) implementation_uid         | PS3.7 D.3.3.2               |
    | –    | 0x55 | (inline) implementation_version     | PS3.7 D.3.3.3               |
    | 0x54 | –    | `RoleSelection`                     | PS3.7 Annex D.3.3.4         |
    | 0x56 | –    | `SopClassExtendedNegotiation`       | PS3.7 Annex D.3.3.5         |
    | 0x57 | –    | `SopClassCommonExtendedNegotiation` | PS3.7 Annex D.3.3.6         |
    | 0x58 | –    | `UserIdentity` (RQ only)            | PS3.7 Annex D.3.3.7         |
    | 0x59 | –    | `UserIdentityAc` (AC only)          | PS3.7 Annex D.3.3.8         |

    Async Operations Window (0x53) is not yet implemented.
    """

    @type t :: %__MODULE__{
            max_pdu_length: pos_integer() | nil,
            implementation_uid: String.t() | nil,
            implementation_version: String.t() | nil,
            role_selections: [Dimse.Pdu.RoleSelection.t()] | nil,
            sop_class_extended: [Dimse.Pdu.SopClassExtendedNegotiation.t()] | nil,
            sop_class_common_extended: [Dimse.Pdu.SopClassCommonExtendedNegotiation.t()] | nil,
            user_identity: Dimse.Pdu.UserIdentity.t() | nil,
            user_identity_ac: Dimse.Pdu.UserIdentityAc.t() | nil
          }

    defstruct [
      :max_pdu_length,
      :implementation_uid,
      :implementation_version,
      :role_selections,
      :sop_class_extended,
      :sop_class_common_extended,
      :user_identity,
      :user_identity_ac
    ]
  end

  defmodule RoleSelection do
    @moduledoc """
    Role Selection sub-item (0x54). PS3.7 Annex D.3.3.4.

    Negotiates SCU/SCP roles for a specific SOP class. Each side can propose
    its role — SCU (service class user), SCP (service class provider), or both.
    """

    @type t :: %__MODULE__{
            sop_class_uid: String.t() | nil,
            scu_role: boolean() | nil,
            scp_role: boolean() | nil
          }

    defstruct [:sop_class_uid, :scu_role, :scp_role]
  end

  defmodule SopClassExtendedNegotiation do
    @moduledoc """
    SOP Class Extended Negotiation sub-item (0x56). PS3.7 Annex D.3.3.5.

    Carries service-class-specific application information for a SOP class.
    The `service_class_application_info` binary is interpreted by the
    service class defined by `sop_class_uid`.
    """

    @type t :: %__MODULE__{
            sop_class_uid: String.t() | nil,
            service_class_application_info: binary() | nil
          }

    defstruct [:sop_class_uid, :service_class_application_info]
  end

  defmodule SopClassCommonExtendedNegotiation do
    @moduledoc """
    SOP Class Common Extended Negotiation sub-item (0x57). PS3.7 Annex D.3.3.6.

    Associates a SOP class with its service class and optionally lists related
    general SOP classes that should also be accepted during negotiation.
    """

    @type t :: %__MODULE__{
            sop_class_uid: String.t() | nil,
            service_class_uid: String.t() | nil,
            related_general_sop_class_uids: [String.t()] | nil
          }

    defstruct [:sop_class_uid, :service_class_uid, :related_general_sop_class_uids]
  end

  defmodule UserIdentity do
    @moduledoc """
    User Identity sub-item for A-ASSOCIATE-RQ (0x58). PS3.7 Annex D.3.3.7.

    Carries SCU identity credentials for authentication by the SCP.

    ## Identity Types

    | Value | Meaning                      |
    |-------|------------------------------|
    | 1     | Username                     |
    | 2     | Username + Passcode          |
    | 3     | Kerberos Service Ticket      |
    | 4     | SAML Assertion               |
    | 5     | JSON Web Token (JWT)         |
    """

    @type t :: %__MODULE__{
            identity_type: pos_integer() | nil,
            positive_response_requested: boolean() | nil,
            primary_field: binary() | nil,
            secondary_field: binary() | nil
          }

    defstruct [:identity_type, :positive_response_requested, :primary_field, :secondary_field]
  end

  defmodule UserIdentityAc do
    @moduledoc """
    User Identity sub-item for A-ASSOCIATE-AC (0x59). PS3.7 Annex D.3.3.8.

    Carries the SCP's server response to the SCU's identity request.
    Only present when the SCU set `positive_response_requested = true`
    and the SCP chooses to respond.
    """

    @type t :: %__MODULE__{
            server_response: binary() | nil
          }

    defstruct [:server_response]
  end
end
