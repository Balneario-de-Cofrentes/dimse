defmodule Dimse.Scu.NSet do
  @moduledoc """
  N-SET SCU — DIMSE-N Set Service Class User.

  Sends an N-SET-RQ to modify attribute values of a managed SOP Instance.

  ## DICOM Reference

  - PS3.7 Section 10.1.3 (N-SET Service)
  """

  import Bitwise

  @doc """
  Builds an N-SET-RQ command set.

  Uses RequestedSOPClassUID (0000,0003) and RequestedSOPInstanceUID (0000,1001).
  """
  @spec build_command_set(String.t(), String.t(), integer(), keyword()) :: map()
  def build_command_set(sop_class_uid, sop_instance_uid, message_id, _opts \\ []) do
    %{
      {0x0000, 0x0003} => sop_class_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.n_set_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0800} => 0x0000,
      {0x0000, 0x1001} => sop_instance_uid
    }
  end

  @doc """
  Sends an N-SET-RQ with modification data and waits for N-SET-RSP.

  Returns `{:ok, status, data}` for successful or warning responses,
  `{:error, {:status, status, data}}` for DIMSE failure statuses,
  or `{:error, reason}` for transport/protocol failures.
  """
  @spec send(pid(), String.t(), String.t(), binary(), keyword()) ::
          {:ok, integer(), binary() | nil}
          | {:error, {:status, integer(), binary() | nil} | term()}
  def send(assoc, sop_class_uid, sop_instance_uid, data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = System.unique_integer([:positive]) &&& 0xFFFF
    command_set = build_command_set(sop_class_uid, sop_instance_uid, message_id, opts)

    case Dimse.Association.request(assoc, command_set, data, timeout) do
      {:ok, response, resp_data} ->
        Dimse.Scu.normalize_n_response(response, resp_data)

      {:error, _} = err ->
        err
    end
  end
end
