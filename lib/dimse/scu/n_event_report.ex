defmodule Dimse.Scu.NEventReport do
  @moduledoc """
  N-EVENT-REPORT SCU — DIMSE-N Event Report Service Class User.

  Sends an N-EVENT-REPORT-RQ to notify the SCP of an event on a
  managed SOP Instance.

  ## DICOM Reference

  - PS3.7 Section 10.1.1 (N-EVENT-REPORT Service)
  """

  import Bitwise

  @doc """
  Builds an N-EVENT-REPORT-RQ command set.

  Uses AffectedSOPClassUID (0000,0002), AffectedSOPInstanceUID (0000,1000),
  and EventTypeID (0000,1002).
  """
  @spec build_command_set(String.t(), String.t(), integer(), integer(), keyword()) :: map()
  def build_command_set(sop_class_uid, sop_instance_uid, message_id, event_type_id, _opts \\ []) do
    %{
      {0x0000, 0x0002} => sop_class_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.n_event_report_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0800} => 0x0000,
      {0x0000, 0x1000} => sop_instance_uid,
      {0x0000, 0x1002} => event_type_id
    }
  end

  @doc """
  Sends an N-EVENT-REPORT-RQ with event data and waits for N-EVENT-REPORT-RSP.

  Returns `{:ok, status, data}` for successful or warning responses,
  `{:error, {:status, status, data}}` for DIMSE failure statuses,
  or `{:error, reason}` for transport/protocol failures.
  """
  @spec send(pid(), String.t(), String.t(), integer(), binary() | nil, keyword()) ::
          {:ok, integer(), binary() | nil}
          | {:error, {:status, integer(), binary() | nil} | term()}
  def send(assoc, sop_class_uid, sop_instance_uid, event_type_id, data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = System.unique_integer([:positive]) &&& 0xFFFF

    command_set =
      build_command_set(sop_class_uid, sop_instance_uid, message_id, event_type_id, opts)
      |> Map.put({0x0000, 0x0800}, if(data, do: 0x0000, else: 0x0101))

    case Dimse.Association.request(assoc, command_set, data, timeout) do
      {:ok, response, resp_data} ->
        Dimse.Scu.normalize_n_response(response, resp_data)

      {:error, _} = err ->
        err
    end
  end
end
