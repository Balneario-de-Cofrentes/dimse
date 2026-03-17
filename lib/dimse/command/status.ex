defmodule Dimse.Command.Status do
  @moduledoc """
  DIMSE status codes.

  Status codes are returned in the (0000,0900) element of DIMSE response
  command sets. They indicate the outcome of the requested operation.

  Defined in PS3.7 Annex C.

  ## Status Categories

  - **Success** (0x0000) — operation completed successfully
  - **Pending** (0xFF00, 0xFF01) — matches remain, more results to follow
  - **Cancel** (0xFE00) — operation cancelled by the SCU
  - **Warning** (0x0001, 0xB000-0xBFFF) — completed with warnings
  - **Failure** (0xA000-0xCFFF) — operation failed

  ## Common Status Codes

  | Code   | Category | Name |
  |--------|----------|------|
  | 0x0000 | Success  | Success |
  | 0xFF00 | Pending  | Pending (matches) |
  | 0xFF01 | Pending  | Pending (optional keys may be unsupported) |
  | 0xFE00 | Cancel   | Cancel |
  | 0x0001 | Warning  | Coercion of data elements |
  | 0xA700 | Failure  | Out of resources |
  | 0xA900 | Failure  | Identifier does not match SOP class |
  | 0xC000 | Failure  | Unable to process |
  | 0xC001 | Failure  | Unable to process (more detail) |
  """

  @doc "Success status (0x0000)."
  def success, do: 0x0000

  @doc "Pending status — more results to follow (0xFF00)."
  def pending, do: 0xFF00

  @doc "Pending status — optional keys may not be supported (0xFF01)."
  def pending_warning, do: 0xFF01

  @doc "Cancel status — operation cancelled (0xFE00)."
  def cancel, do: 0xFE00

  @doc "Coercion warning status (0x0001)."
  def warning_coercion, do: 0x0001

  @doc "Out of resources failure (0xA700)."
  def failure_out_of_resources, do: 0xA700

  @doc "Identifier does not match SOP class failure (0xA900)."
  def failure_identifier_mismatch, do: 0xA900

  @doc "Unable to process failure (0xC000)."
  def failure_unable_to_process, do: 0xC000

  @doc "Returns the category of a status code."
  @spec category(integer()) :: :success | :pending | :cancel | :warning | :failure
  def category(0x0000), do: :success
  def category(status) when status in [0xFF00, 0xFF01], do: :pending
  def category(0xFE00), do: :cancel
  def category(0x0001), do: :warning
  def category(status) when status >= 0xB000 and status <= 0xBFFF, do: :warning
  def category(_status), do: :failure
end
