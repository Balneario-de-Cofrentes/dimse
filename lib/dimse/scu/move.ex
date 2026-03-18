defmodule Dimse.Scu.Move do
  @moduledoc """
  C-MOVE SCU — DICOM Query/Retrieve Service Class User (MOVE).

  Sends a C-MOVE-RQ to a remote SCP to retrieve instances. The SCP pushes
  the matching instances to a third-party AE via outbound C-STORE sub-operations.

  ## Usage

      {:ok, assoc} = Dimse.Scu.open("192.168.1.10", 11112,
        calling_ae: "MY_SCU",
        called_ae: "REMOTE_SCP",
        abstract_syntaxes: ["1.2.840.10008.5.1.4.1.2.2.2"]  # Study Root MOVE
      )

      {:ok, result} = Dimse.Scu.Move.retrieve(assoc, sop_class_uid, query_data, "DEST_AE")
      # result.completed, result.failed, result.warning

  ## SOP Classes (PS3.4)

  - Patient Root Q/R - MOVE: `1.2.840.10008.5.1.4.1.2.1.2`
  - Study Root Q/R - MOVE: `1.2.840.10008.5.1.4.1.2.2.2`

  ## DICOM Reference

  - PS3.7 Section 9.1.4 (C-MOVE Service)
  - PS3.4 Annex C (Query/Retrieve Service Class)
  """

  import Bitwise

  @patient_root_move "1.2.840.10008.5.1.4.1.2.1.2"
  @study_root_move "1.2.840.10008.5.1.4.1.2.2.2"

  @doc """
  Maps a query level atom to its C-MOVE SOP Class UID.

  ## Supported levels

    * `:patient` — Patient Root Query/Retrieve Information Model - MOVE
    * `:study` — Study Root Query/Retrieve Information Model - MOVE
  """
  @spec sop_class_uid(atom()) :: String.t() | nil
  def sop_class_uid(:patient), do: @patient_root_move
  def sop_class_uid(:study), do: @study_root_move
  def sop_class_uid(_), do: nil

  @doc """
  Builds a C-MOVE-RQ command set.

  ## Parameters

    * `sop_class_uid` — the Query/Retrieve SOP Class UID
    * `message_id` — unique message identifier
    * `move_destination` — AE title of the move destination

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
  """
  @spec build_command_set(String.t(), integer(), String.t(), keyword()) :: map()
  def build_command_set(sop_class_uid, message_id, move_destination, opts \\ []) do
    priority = Keyword.get(opts, :priority, 0x0000)

    %{
      {0x0000, 0x0002} => sop_class_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.c_move_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0600} => move_destination,
      {0x0000, 0x0700} => priority,
      {0x0000, 0x0800} => 0x0000
    }
  end

  @doc """
  Sends a C-MOVE-RQ and waits for the final response with sub-operation counts.

  The SCP will push instances to the move destination via C-STORE sub-operations
  and send C-MOVE-RSP Pending messages with updated sub-operation counts. The
  final C-MOVE-RSP indicates success or failure.

  ## Parameters

    * `assoc` — association pid from `Dimse.Scu.open/3`
    * `sop_class_uid` — Query/Retrieve SOP Class UID
    * `query_data` — encoded query identifier data set
    * `move_destination` — AE title of the destination SCP

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
    * `:timeout` — response timeout in ms (default: `30_000`)

  Returns `{:ok, %{completed: n, failed: n, warning: n}}` on success,
  `{:error, {:status, code}}` for non-success final status,
  `{:error, reason}` for transport or protocol errors.
  """
  @spec retrieve(pid(), String.t(), binary(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def retrieve(assoc, sop_class_uid, query_data, move_destination, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = System.unique_integer([:positive]) &&& 0xFFFF
    command_set = build_command_set(sop_class_uid, message_id, move_destination, opts)

    case Dimse.Association.find_request(assoc, command_set, query_data, timeout) do
      {:ok, response, _results} ->
        case Dimse.Command.status(response) do
          status when status in [0x0000, 0xFE00] ->
            {:ok, extract_sub_op_counts(response)}

          status ->
            {:error, {:status, status}}
        end

      {:error, _} = err ->
        err
    end
  end

  defp extract_sub_op_counts(response) do
    %{
      completed: Map.get(response, {0x0000, 0x1021}, 0),
      failed: Map.get(response, {0x0000, 0x1022}, 0),
      warning: Map.get(response, {0x0000, 0x1023}, 0)
    }
  end
end
