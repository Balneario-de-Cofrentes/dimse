defmodule Dimse.Scu.NGet do
  @moduledoc """
  N-GET SCU — DIMSE-N Get Service Class User.

  Sends an N-GET-RQ to retrieve attribute values from a managed SOP Instance.

  ## Usage

      {:ok, assoc} = Dimse.Scu.open("192.168.1.10", 11112,
        calling_ae: "MY_SCU",
        called_ae: "REMOTE_SCP",
        abstract_syntaxes: ["1.2.840.10008.5.1.4.34.6.1"]
      )

      {:ok, status, data} = Dimse.Scu.NGet.query(assoc, sop_class_uid, sop_instance_uid)

  ## DICOM Reference

  - PS3.7 Section 10.1.2 (N-GET Service)
  """

  import Bitwise

  @doc """
  Builds an N-GET-RQ command set.

  Uses RequestedSOPClassUID (0000,0003) and RequestedSOPInstanceUID (0000,1001).

  ## Options

    * `:attribute_identifier_list` — list of `{group, element}` tags to retrieve
  """
  @spec build_command_set(String.t(), String.t(), integer(), keyword()) :: map()
  def build_command_set(sop_class_uid, sop_instance_uid, message_id, opts \\ []) do
    %{
      {0x0000, 0x0003} => sop_class_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.n_get_rq(),
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0800} => 0x0101,
      {0x0000, 0x1001} => sop_instance_uid
    }
    |> maybe_put({0x0000, 0x1005}, Keyword.get(opts, :attribute_identifier_list))
  end

  @doc """
  Sends an N-GET-RQ and waits for N-GET-RSP.

  Returns `{:ok, status, data}` for successful or warning responses,
  `{:error, {:status, status, data}}` for DIMSE failure statuses,
  or `{:error, reason}` for transport/protocol failures.
  """
  @spec query(pid(), String.t(), String.t(), keyword()) ::
          {:ok, integer(), binary() | nil}
          | {:error, {:status, integer(), binary() | nil} | term()}
  def query(assoc, sop_class_uid, sop_instance_uid, opts \\ []) do
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

  defp maybe_put(map, _tag, nil), do: map
  defp maybe_put(map, tag, value), do: Map.put(map, tag, value)
end
