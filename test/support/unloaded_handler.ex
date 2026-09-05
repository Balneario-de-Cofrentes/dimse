defmodule Dimse.TestSupport.UnloadedHandler do
  @moduledoc false
  # Compiled to disk under test/support so it can be purged from the VM and
  # reloaded on demand. Used to prove that optional handler callbacks are
  # honoured even when the handler module has not been loaded yet.

  @behaviour Dimse.Handler

  @impl true
  def supported_abstract_syntaxes, do: ["1.2.840.10008.5.1.4.1.1.2"]

  @impl true
  def handle_echo(_command_set, _state), do: {:ok, 0x0000}

  @impl true
  def validate_association(_rq, _state), do: {:error, :calling_ae_not_allowed}
end
