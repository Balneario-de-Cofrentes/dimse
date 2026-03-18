defmodule Dimse.Scu.Find do
  @moduledoc """
  C-FIND SCU — DICOM Query Service Class User.

  Sends a C-FIND-RQ to a remote SCP to query DICOM data sets, equivalent to
  DCMTK's `findscu` or dcm4che's `findscu`.

  ## Usage

      {:ok, assoc} = Dimse.Scu.open("192.168.1.10", 11112,
        calling_ae: "MY_SCU",
        called_ae: "REMOTE_SCP",
        abstract_syntaxes: ["1.2.840.10008.5.1.4.1.2.2.1"]  # Study Root
      )

      {:ok, results} = Dimse.Scu.Find.query(assoc, "1.2.840.10008.5.1.4.1.2.2.1", query_data)

  ## Query SOP Classes (PS3.4)

  - Patient Root Q/R - FIND: `1.2.840.10008.5.1.4.1.2.1.1`
  - Study Root Q/R - FIND: `1.2.840.10008.5.1.4.1.2.2.1`
  - Modality Worklist - FIND: `1.2.840.10008.5.1.4.31`

  ## DICOM Reference

  - PS3.7 Section 9.1.2 (C-FIND Service)
  - PS3.4 Annex C (Query/Retrieve Service Class)
  """

  import Bitwise

  @patient_root_find "1.2.840.10008.5.1.4.1.2.1.1"
  @study_root_find "1.2.840.10008.5.1.4.1.2.2.1"
  @worklist_find "1.2.840.10008.5.1.4.31"

  @doc """
  Maps a query level atom to its SOP Class UID.

  ## Supported levels

    * `:patient` — Patient Root Query/Retrieve Information Model - FIND
    * `:study` — Study Root Query/Retrieve Information Model - FIND
    * `:worklist` — Modality Worklist Information Model - FIND

  Returns `nil` for unknown levels.
  """
  @spec sop_class_uid(atom()) :: String.t() | nil
  def sop_class_uid(:patient), do: @patient_root_find
  def sop_class_uid(:study), do: @study_root_find
  def sop_class_uid(:worklist), do: @worklist_find
  def sop_class_uid(_), do: nil

  @doc """
  Builds a C-FIND-RQ command set.

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
      {0x0000, 0x0100} => Dimse.Command.Fields.c_find_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0700} => priority,
      {0x0000, 0x0800} => 0x0000
    }
  end

  @doc """
  Sends a C-FIND-RQ with the given query identifier and collects all matching results.

  The SCU sends a single C-FIND-RQ with the query identifier (encoded data set),
  then receives zero or more C-FIND-RSP messages with Pending status (0xFF00/0xFF01),
  each containing a matching data set. The final C-FIND-RSP has Success status
  (0x0000) and no data set.

  ## Parameters

    * `assoc` — association pid from `Dimse.Scu.open/3`
    * `sop_class_uid` — Query/Retrieve SOP Class UID
    * `query_data` — encoded query identifier data set

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
    * `:timeout` — response timeout in ms (default: `30_000`)

  Returns `{:ok, [binary()]}` with matching data sets on success,
  `{:error, {:cancelled, results}}` when the peer ends the operation with
  Cancel status after sending partial results,
  `{:error, {:status, code}}` for other non-success final statuses,
  `{:error, reason}` for transport or protocol errors.
  """
  @spec query(pid(), String.t(), binary(), keyword()) :: {:ok, [binary()]} | {:error, term()}
  def query(assoc, sop_class_uid, query_data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = System.unique_integer([:positive]) &&& 0xFFFF
    command_set = build_command_set(sop_class_uid, message_id, opts)

    case Dimse.Association.find_request(assoc, command_set, query_data, timeout) do
      {:ok, response, results} ->
        case Dimse.Command.status(response) do
          0x0000 -> {:ok, results}
          0xFE00 -> {:error, {:cancelled, results}}
          status -> {:error, {:status, status}}
        end

      {:error, _} = err ->
        err
    end
  end
end
