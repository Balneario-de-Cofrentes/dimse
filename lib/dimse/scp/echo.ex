defmodule Dimse.Scp.Echo do
  @moduledoc """
  Built-in C-ECHO SCP (Verification SOP Class).

  Handles C-ECHO-RQ commands by returning a C-ECHO-RSP with status Success
  (0x0000). This is the DICOM equivalent of "ping" — it verifies that a
  DICOM association can be established and that the SCP is responsive.

  This module is used as the default echo handler and can also serve as a
  reference implementation for other SCP service class handlers.

  ## DICOM Reference

  - Verification SOP Class UID: `1.2.840.10008.1.1`
  - PS3.7 Section 9.1.5 (C-ECHO Service)
  - PS3.4 Section A.4 (Verification Service Class)

  ## Wire Sequence

      SCU                          SCP
       │                            │
       │── C-ECHO-RQ ──────────────>│
       │                            │
       │<───────────── C-ECHO-RSP ──│
       │            (status 0x0000) │
  """

  @doc """
  Handles a C-ECHO-RQ command.

  Always returns `{:ok, 0x0000}` (Success) per PS3.7 Section 9.1.5.4.
  """
  @spec handle(command :: map(), state :: Dimse.Association.State.t()) ::
          {:ok, integer()}
  def handle(_command, _state) do
    {:ok, 0x0000}
  end
end
