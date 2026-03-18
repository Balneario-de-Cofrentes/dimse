defmodule Dimse.Scu.NDelete do
  @moduledoc """
  N-DELETE SCU — DIMSE-N Delete Service Class User.

  Sends an N-DELETE-RQ to delete a managed SOP Instance.

  ## DICOM Reference

  - PS3.7 Section 10.1.6 (N-DELETE Service)
  """

  import Bitwise

  @doc """
  Builds an N-DELETE-RQ command set.

  Uses RequestedSOPClassUID (0000,0003) and RequestedSOPInstanceUID (0000,1001).
  No data set follows (CommandDataSetType = 0x0101).
  """
  @spec build_command_set(String.t(), String.t(), integer(), keyword()) :: map()
  def build_command_set(sop_class_uid, sop_instance_uid, message_id, _opts \\ []) do
    %{
      {0x0000, 0x0003} => sop_class_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.n_delete_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0800} => 0x0101,
      {0x0000, 0x1001} => sop_instance_uid
    }
  end

  @doc """
  Sends an N-DELETE-RQ and waits for N-DELETE-RSP.

  Returns `{:ok, status, nil}` for successful or warning responses,
  `{:error, {:status, status, nil}}` for DIMSE failure statuses,
  or `{:error, reason}` for transport/protocol failures.
  """
  @spec send(pid(), String.t(), String.t(), keyword()) ::
          {:ok, integer(), nil} | {:error, {:status, integer(), nil} | term()}
  def send(assoc, sop_class_uid, sop_instance_uid, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = System.unique_integer([:positive]) &&& 0xFFFF
    command_set = build_command_set(sop_class_uid, sop_instance_uid, message_id, opts)

    case Dimse.Association.request(assoc, command_set, nil, timeout) do
      {:ok, response, data} ->
        Dimse.Scu.normalize_n_response(response, data)

      {:error, _} = err ->
        err
    end
  end
end
