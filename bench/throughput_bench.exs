# Throughput benchmark: measures operations on a PERSISTENT association.
# Opens one connection, sends N operations, measures per-op cost.
# This isolates actual DIMSE processing time from TCP+negotiation overhead.

defmodule ThroughputHandler do
  @behaviour Dimse.Handler

  @ct "1.2.840.10008.5.1.4.1.1.2"

  @impl true
  def supported_abstract_syntaxes, do: ["1.2.840.10008.1.1", @ct]

  @impl true
  def handle_echo(_command, _state), do: {:ok, 0x0000}

  @impl true
  def handle_store(_command, _data, _state), do: {:ok, 0x0000}

  @impl true
  def handle_find(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_move(_command, _query, _state), do: {:ok, []}

  @impl true
  def handle_get(_command, _query, _state), do: {:ok, []}
end

{:ok, ref} = Dimse.start_listener(port: 0, handler: ThroughputHandler)
port = :ranch.get_port(ref)

ct_uid = "1.2.840.10008.5.1.4.1.1.2"
sop_uid = "1.2.3.4.5"

data_1kb = :crypto.strong_rand_bytes(1024)
data_64kb = :crypto.strong_rand_bytes(65_536)

# Open persistent associations
{:ok, echo_assoc} =
  Dimse.connect("127.0.0.1", port,
    calling_ae: "BENCH",
    called_ae: "DIMSE",
    abstract_syntaxes: ["1.2.840.10008.1.1"]
  )

{:ok, store_assoc} =
  Dimse.connect("127.0.0.1", port,
    calling_ae: "BENCH",
    called_ae: "DIMSE",
    abstract_syntaxes: [ct_uid]
  )

IO.puts("=== Persistent-connection throughput benchmarks ===")
IO.puts("Listener on port #{port}")
IO.puts("")

Benchee.run(
  %{
    "C-ECHO (no connect)" => fn ->
      :ok = Dimse.echo(echo_assoc, timeout: 5_000)
    end,
    "C-STORE 1KB (no connect)" => fn ->
      :ok = Dimse.store(store_assoc, ct_uid, sop_uid, data_1kb, timeout: 5_000)
    end,
    "C-STORE 64KB (no connect)" => fn ->
      :ok = Dimse.store(store_assoc, ct_uid, sop_uid, data_64kb, timeout: 5_000)
    end
  },
  time: 5,
  warmup: 2,
  memory_time: 0,
  print: [configuration: false]
)

Dimse.release(echo_assoc, 5_000)
Dimse.release(store_assoc, 5_000)
Dimse.stop_listener(ref)
