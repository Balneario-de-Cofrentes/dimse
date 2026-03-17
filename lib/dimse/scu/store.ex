defmodule Dimse.Scu.Store do
  @moduledoc """
  C-STORE SCU — DICOM Storage Service Class User.

  Sends a C-STORE-RQ to a remote SCP to store a DICOM instance, equivalent to
  DCMTK's `storescu` or dcm4che's `storescu`.

  ## Usage

      {:ok, assoc} = Dimse.Scu.open("192.168.1.10", 11112,
        calling_ae: "MY_SCU",
        called_ae: "REMOTE_SCP",
        abstract_syntaxes: ["1.2.840.10008.5.1.4.1.1.2"]  # CT Image Storage
      )

      :ok = Dimse.Scu.Store.send(assoc, sop_class_uid, sop_instance_uid, data_set)

  ## DICOM Reference

  - PS3.7 Section 9.1.1 (C-STORE Service)
  - PS3.4 Annex B (Storage Service Class)
  """

  import Bitwise

  @doc """
  Sends a C-STORE-RQ with the given data set and waits for C-STORE-RSP.

  ## Parameters

    * `assoc` — association pid from `Dimse.Scu.open/3`
    * `sop_class_uid` — SOP Class UID of the instance (e.g., CT Image Storage)
    * `sop_instance_uid` — SOP Instance UID uniquely identifying the instance
    * `data` — encoded data set binary

  ## Options

    * `:priority` — request priority (default: `0x0000` medium)
    * `:move_originator_ae` — AE title of the C-MOVE originator
    * `:move_originator_message_id` — message ID from the C-MOVE request
    * `:timeout` — response timeout in ms (default: `30_000`)

  Returns `:ok` if the response status is Success (0x0000),
  `{:error, {:status, code}}` for non-success DIMSE status,
  `{:error, reason}` for transport or protocol errors.
  """
  @spec send(pid(), String.t(), String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def send(assoc, sop_class_uid, sop_instance_uid, data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    priority = Keyword.get(opts, :priority, 0x0000)

    command_set =
      %{
        {0x0000, 0x0002} => sop_class_uid,
        {0x0000, 0x0100} => Dimse.Command.Fields.c_store_rq(),
        {0x0000, 0x0110} => System.unique_integer([:positive]) &&& 0xFFFF,
        {0x0000, 0x0700} => priority,
        {0x0000, 0x0800} => 0x0000,
        {0x0000, 0x1000} => sop_instance_uid
      }
      |> maybe_put({0x0000, 0x0300}, Keyword.get(opts, :move_originator_ae))
      |> maybe_put({0x0000, 0x1031}, Keyword.get(opts, :move_originator_message_id))

    case Dimse.Association.request(assoc, command_set, data, timeout) do
      {:ok, response, _data} ->
        case Dimse.Command.status(response) do
          0x0000 -> :ok
          status -> {:error, {:status, status}}
        end

      {:error, _} = err ->
        err
    end
  end

  defp maybe_put(map, _tag, nil), do: map
  defp maybe_put(map, tag, value), do: Map.put(map, tag, value)
end
