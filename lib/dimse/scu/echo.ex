defmodule Dimse.Scu.Echo do
  @moduledoc """
  C-ECHO SCU — DICOM Verification Service Class User.

  Sends a C-ECHO-RQ to a remote SCP to verify connectivity, equivalent to
  DCMTK's `echoscu` or dcm4che's `storescu --echo`.

  ## Usage

      {:ok, assoc} = Dimse.Scu.open("192.168.1.10", 11112,
        calling_ae: "MY_SCU",
        called_ae: "REMOTE_SCP",
        abstract_syntaxes: ["1.2.840.10008.1.1"]
      )

      :ok = Dimse.Scu.Echo.verify(assoc)

  ## DICOM Reference

  - Verification SOP Class UID: `1.2.840.10008.1.1`
  - PS3.7 Section 9.1.5 (C-ECHO Service)
  - PS3.4 Section A.4 (Verification Service Class)
  """

  import Bitwise

  @verification_uid "1.2.840.10008.1.1"

  @doc """
  Sends a C-ECHO-RQ and waits for C-ECHO-RSP.

  Returns `:ok` if the response status is Success (0x0000),
  `{:error, status_code}` otherwise.
  """
  @spec verify(pid(), keyword()) :: :ok | {:error, term()}
  def verify(assoc, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    command_set = %{
      {0x0000, 0x0002} => @verification_uid,
      {0x0000, 0x0100} => Dimse.Command.Fields.c_echo_rq(),
      {0x0000, 0x0110} => System.unique_integer([:positive]) &&& 0xFFFF,
      {0x0000, 0x0800} => 0x0101
    }

    case Dimse.Association.request(assoc, command_set, nil, timeout) do
      {:ok, response, _data} ->
        case Dimse.Command.status(response) do
          0x0000 -> :ok
          status -> {:error, {:status, status}}
        end

      {:error, _} = err ->
        err
    end
  end
end
