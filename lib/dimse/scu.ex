defmodule Dimse.Scu do
  @moduledoc """
  SCU (Service Class User) client API.

  Provides functions to establish outbound DICOM associations and execute
  DIMSE-C operations against remote SCPs. This is the client-side counterpart
  to the SCP behaviour defined in `Dimse.Handler`.

  ## Usage

      # Open an association
      {:ok, assoc} = Dimse.Scu.open("192.168.1.10", 11112,
        calling_ae: "MY_SCU",
        called_ae: "REMOTE_SCP",
        abstract_syntaxes: ["1.2.840.10008.1.1"]  # Verification
      )

      # Execute operations
      :ok = Dimse.Scu.Echo.verify(assoc)

      # Release the association
      :ok = Dimse.Scu.release(assoc)

  ## Association Management

  The SCU opens a TCP connection, sends an A-ASSOCIATE-RQ, waits for the
  A-ASSOCIATE-AC, and returns a `Dimse.Association` pid. All DIMSE operations
  are then sent as GenServer calls to this pid.

  ## Error Handling

  - Connection refused → `{:error, :econnrefused}`
  - Association rejected → `{:error, {:rejected, result, source, reason}}`
  - Timeout → `{:error, :timeout}`
  - Unexpected abort → `{:error, {:aborted, source, reason}}`
  """

  @doc """
  Opens a DICOM association to a remote AE.

  Returns `{:ok, association_pid}` or `{:error, reason}`.
  """
  @spec open(String.t(), pos_integer(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(_host, _port, _opts \\ []) do
    {:error, :not_implemented}
  end

  @doc """
  Sends an A-RELEASE-RQ and waits for A-RELEASE-RP.
  """
  @spec release(pid()) :: :ok | {:error, term()}
  def release(_assoc) do
    {:error, :not_implemented}
  end

  @doc """
  Sends an A-ABORT to forcefully terminate the association.
  """
  @spec abort(pid()) :: :ok | {:error, term()}
  def abort(_assoc) do
    {:error, :not_implemented}
  end
end
