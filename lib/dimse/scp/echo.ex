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

  @behaviour Dimse.Handler

  @verification_uid "1.2.840.10008.1.1"

  @doc """
  Returns the supported abstract syntaxes (Verification SOP Class only).
  """
  @impl Dimse.Handler
  def supported_abstract_syntaxes, do: [@verification_uid]

  @impl Dimse.Handler
  def handle_echo(_command, _state), do: {:ok, 0x0000}

  @impl Dimse.Handler
  def handle_store(_command, _data, _state), do: {:error, 0xC000, "not supported"}

  @impl Dimse.Handler
  def handle_find(_command, _query, _state), do: {:error, 0xC000, "not supported"}

  @impl Dimse.Handler
  def handle_move(_command, _query, _state), do: {:error, 0xC000, "not supported"}

  @impl Dimse.Handler
  def handle_get(_command, _query, _state), do: {:error, 0xC000, "not supported"}
end
