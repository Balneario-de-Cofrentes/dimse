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

  @doc """
  Sends a C-ECHO-RQ and waits for C-ECHO-RSP.

  Returns `:ok` if the response status is Success (0x0000),
  `{:error, status_code}` otherwise.
  """
  @spec verify(pid(), keyword()) :: :ok | {:error, term()}
  def verify(_assoc, _opts \\ []) do
    {:error, :not_implemented}
  end
end
