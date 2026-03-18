defmodule Dimse.Scu.Get do
  @moduledoc """
  C-GET SCU — DICOM Query/Retrieve Service Class User (GET).

  Sends a C-GET-RQ to a remote SCP to retrieve instances on the same
  association. The SCP sends matching instances back as interleaved C-STORE
  sub-operations on the same association, and the SCU auto-accepts them.

  ## Usage

      {:ok, assoc} = Dimse.Scu.open("192.168.1.10", 11112,
        calling_ae: "MY_SCU",
        called_ae: "REMOTE_SCP",
        abstract_syntaxes: [
          "1.2.840.10008.5.1.4.1.2.2.3",  # Study Root GET
          "1.2.840.10008.5.1.4.1.1.2"      # CT Image Storage (to receive)
        ]
      )

      {:ok, data_sets} = Dimse.Scu.Get.retrieve(assoc, sop_class_uid, query_data)

  ## SOP Classes (PS3.4)

  - Patient Root Q/R - GET: `1.2.840.10008.5.1.4.1.2.1.3`
  - Study Root Q/R - GET: `1.2.840.10008.5.1.4.1.2.2.3`

  ## DICOM Reference

  - PS3.7 Section 9.1.3 (C-GET Service)
  - PS3.4 Annex C (Query/Retrieve Service Class)
  """

  import Bitwise

  @patient_root_get "1.2.840.10008.5.1.4.1.2.1.3"
  @study_root_get "1.2.840.10008.5.1.4.1.2.2.3"

  @doc """
  Maps a query level atom to its C-GET SOP Class UID.

  ## Supported levels

    * `:patient` — Patient Root Query/Retrieve Information Model - GET
    * `:study` — Study Root Query/Retrieve Information Model - GET
  """
  @spec sop_class_uid(atom()) :: String.t() | nil
  def sop_class_uid(:patient), do: @patient_root_get
  def sop_class_uid(:study), do: @study_root_get
  def sop_class_uid(_), do: nil

  @doc """
  Builds a C-GET-RQ command set.

  ## Parameters

    * `sop_class_uid` — the Query/Retrieve SOP Class UID
    * `message_id` — unique message identifier

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
  """
  @spec build_command_set(String.t(), integer(), keyword()) :: map()
  def build_command_set(sop_class_uid, message_id, opts \\ []) do
    priority = Keyword.get(opts, :priority, 0x0000)

    %{
      {0x0000, 0x0002} => sop_class_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.c_get_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0700} => priority,
      {0x0000, 0x0800} => 0x0000
    }
  end

  @doc """
  Sends a C-GET-RQ and collects received instances from C-STORE sub-operations.

  The SCU sends a C-GET-RQ, then the SCP sends C-STORE sub-operations back
  on the same association. The SCU auto-accepts each C-STORE and accumulates
  the data sets. The final C-GET-RSP ends the retrieval.

  ## Parameters

    * `assoc` — association pid from `Dimse.Scu.open/3`
    * `sop_class_uid` — Query/Retrieve SOP Class UID
    * `query_data` — encoded query identifier data set

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
    * `:timeout` — response timeout in ms (default: `30_000`)

  Returns `{:ok, [binary()]}` with the received data sets on success,
  `{:error, {:status, code}}` for non-success final status,
  `{:error, reason}` for transport or protocol errors.
  """
  @spec retrieve(pid(), String.t(), binary(), keyword()) ::
          {:ok, [binary()]} | {:error, term()}
  def retrieve(assoc, sop_class_uid, query_data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = System.unique_integer([:positive]) &&& 0xFFFF
    command_set = build_command_set(sop_class_uid, message_id, opts)

    case Dimse.Association.get_request(assoc, command_set, query_data, timeout) do
      {:ok, response, results} ->
        case Dimse.Command.status(response) do
          status when status in [0x0000, 0xFE00] -> {:ok, results}
          status -> {:error, {:status, status}}
        end

      {:error, _} = err ->
        err
    end
  end
end
