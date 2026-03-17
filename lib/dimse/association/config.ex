defmodule Dimse.Association.Config do
  @moduledoc """
  Configuration struct for association parameters.

  Carries timeout values, AE titles, PDU limits, and other settings
  needed by `Dimse.Association` during its lifecycle.

  ## Defaults

  - `:ae_title` — `"DIMSE"`
  - `:max_pdu_length` — `16_384` (16 KB, DICOM minimum)
  - `:max_associations` — `200`
  - `:association_timeout` — `600_000` ms (10 minutes)
  - `:dimse_timeout` — `30_000` ms (30 seconds)
  - `:artim_timeout` — `30_000` ms (ARTIM timer per PS3.8 Section 9.1.4)
  - `:num_acceptors` — `10`
  """

  @type t :: %__MODULE__{
          ae_title: String.t(),
          max_pdu_length: pos_integer(),
          max_associations: pos_integer(),
          association_timeout: pos_integer(),
          dimse_timeout: pos_integer(),
          artim_timeout: pos_integer(),
          num_acceptors: pos_integer()
        }

  defstruct ae_title: "DIMSE",
            max_pdu_length: 16_384,
            max_associations: 200,
            association_timeout: 600_000,
            dimse_timeout: 30_000,
            artim_timeout: 30_000,
            num_acceptors: 10
end
