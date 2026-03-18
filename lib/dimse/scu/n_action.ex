defmodule Dimse.Scu.NAction do
  @moduledoc """
  N-ACTION SCU — DIMSE-N Action Service Class User.

  Sends an N-ACTION-RQ to request an action on a managed SOP Instance.

  ## DICOM Reference

  - PS3.7 Section 10.1.4 (N-ACTION Service)
  """

  import Bitwise

  @doc """
  Builds an N-ACTION-RQ command set.

  Uses RequestedSOPClassUID (0000,0003), RequestedSOPInstanceUID (0000,1001),
  and ActionTypeID (0000,1008).
  """
  @spec build_command_set(String.t(), String.t(), integer(), integer(), keyword()) :: map()
  def build_command_set(sop_class_uid, sop_instance_uid, message_id, action_type_id, _opts \\ []) do
    %{
      {0x0000, 0x0003} => sop_class_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.n_action_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0800} => 0x0000,
      {0x0000, 0x1001} => sop_instance_uid,
      {0x0000, 0x1008} => action_type_id
    }
  end

  @doc """
  Sends an N-ACTION-RQ with action info and waits for N-ACTION-RSP.

  Returns `{:ok, status, data}` on success, `{:error, reason}` on failure.
  """
  @spec send(pid(), String.t(), String.t(), integer(), binary() | nil, keyword()) ::
          {:ok, integer(), binary() | nil} | {:error, term()}
  def send(assoc, sop_class_uid, sop_instance_uid, action_type_id, data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = System.unique_integer([:positive]) &&& 0xFFFF

    command_set =
      build_command_set(sop_class_uid, sop_instance_uid, message_id, action_type_id, opts)
      |> Map.put({0x0000, 0x0800}, if(data, do: 0x0000, else: 0x0101))

    case Dimse.Association.request(assoc, command_set, data, timeout) do
      {:ok, response, resp_data} ->
        {:ok, Dimse.Command.status(response), resp_data}

      {:error, _} = err ->
        err
    end
  end
end
