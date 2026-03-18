defmodule Dimse.Scu.NCreate do
  @moduledoc """
  N-CREATE SCU — DIMSE-N Create Service Class User.

  Sends an N-CREATE-RQ to create a new managed SOP Instance.

  ## DICOM Reference

  - PS3.7 Section 10.1.5 (N-CREATE Service)
  """

  import Bitwise

  @doc """
  Builds an N-CREATE-RQ command set.

  Uses AffectedSOPClassUID (0000,0002). N-CREATE is the exception among
  N-GET/N-SET/N-ACTION/N-DELETE — it uses Affected, not Requested tags.

  ## Options

    * `:sop_instance_uid` — optional AffectedSOPInstanceUID to propose
  """
  @spec build_command_set(String.t(), integer(), keyword()) :: map()
  def build_command_set(sop_class_uid, message_id, opts \\ []) do
    %{
      {0x0000, 0x0002} => sop_class_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.n_create_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0800} => 0x0000
    }
    |> maybe_put({0x0000, 0x1000}, Keyword.get(opts, :sop_instance_uid))
  end

  @doc """
  Sends an N-CREATE-RQ with attribute data and waits for N-CREATE-RSP.

  Returns `{:ok, status, data}` for successful or warning responses,
  `{:error, {:status, status, data}}` for DIMSE failure statuses,
  or `{:error, reason}` for transport/protocol failures.
  """
  @spec send(pid(), String.t(), binary() | nil, keyword()) ::
          {:ok, integer(), binary() | nil}
          | {:error, {:status, integer(), binary() | nil} | term()}
  def send(assoc, sop_class_uid, data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = System.unique_integer([:positive]) &&& 0xFFFF
    command_set = build_command_set(sop_class_uid, message_id, opts)

    case Dimse.Association.request(assoc, command_set, data, timeout) do
      {:ok, response, resp_data} ->
        Dimse.Scu.normalize_n_response(response, resp_data)

      {:error, _} = err ->
        err
    end
  end

  defp maybe_put(map, _tag, nil), do: map
  defp maybe_put(map, tag, value), do: Map.put(map, tag, value)
end
