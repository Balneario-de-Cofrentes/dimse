defmodule Dimse.ConnectionHandler do
  @moduledoc """
  Ranch protocol callback for incoming DICOM TCP connections.

  Implements the `:ranch_protocol` behaviour. When Ranch accepts a new TCP
  connection, it calls `start_link/3` which starts a `Dimse.Association`
  GenServer under the DynamicSupervisor.

  This module is the bridge between Ranch's acceptor pool and the DIMSE
  association lifecycle. It:

  1. Receives the accepted socket from Ranch
  2. Starts a `Dimse.Association` process under the DynamicSupervisor
  3. Hands off socket ownership to the new process
  4. Returns, freeing the acceptor to accept more connections

  If the DynamicSupervisor has reached `max_children`, the connection is
  rejected with an A-ASSOCIATE-RJ PDU and the socket is closed.
  """

  @behaviour :ranch_protocol

  @doc false
  @impl true
  def start_link(ref, transport, opts) do
    Dimse.Association.start_link([{:ranch_ref, ref}, {:transport, transport} | opts])
  end
end
