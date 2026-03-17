defmodule Dimse.Listener do
  @moduledoc """
  Ranch listener lifecycle management.

  Wraps `:ranch.child_spec/5` to start a TCP listener that accepts DICOM
  associations. Each accepted connection is handed off to
  `Dimse.ConnectionHandler`, which spawns a `Dimse.Association` GenServer.

  ## Usage

  Add to your supervision tree:

      children = [
        {Dimse.Listener, port: 11112, handler: MyApp.DicomHandler}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  Or start dynamically:

      {:ok, ref} = Dimse.start_listener(port: 11112, handler: MyApp.DicomHandler)

  ## Options

  See `Dimse.start_listener/1` for available options.
  """

  @doc """
  Returns a child spec for the Ranch listener.

  Used when adding the listener to a supervision tree.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(_opts) do
    {:error, :not_implemented}
  end
end
