defmodule Dimse.ConnectionHandler do
  @moduledoc """
  Ranch protocol callback for incoming DICOM TCP connections.

  Implements the `:ranch_protocol` behaviour. When Ranch accepts a new TCP
  connection, it calls `start_link/3` which starts a `Dimse.Association`
  GenServer that takes ownership of the socket.

  This module is the bridge between Ranch's acceptor pool and the DIMSE
  association lifecycle.
  """

  @behaviour :ranch_protocol

  @doc false
  @impl true
  def start_link(ref, transport, opts) do
    association_opts = [
      {:ranch_ref, ref},
      {:transport, transport},
      {:mode, :scp}
      | opts
    ]

    Dimse.Association.start_link(association_opts)
  end
end
