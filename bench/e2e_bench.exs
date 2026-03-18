# End-to-end throughput benchmark: measures actual DIMSE operations over TCP

defmodule BenchHandler do
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

# Start listener
{:ok, ref} = Dimse.start_listener(port: 0, handler: BenchHandler)
port = :ranch.get_port(ref)

ct_uid = "1.2.840.10008.5.1.4.1.1.2"
data_4kb = :crypto.strong_rand_bytes(4096)
data_64kb = :crypto.strong_rand_bytes(65_536)
data_1mb = :crypto.strong_rand_bytes(1_048_576)

# Helper: open an association, run the bench function N times, release
run_with_assoc = fn syntaxes, fun ->
  {:ok, assoc} =
    Dimse.connect("127.0.0.1", port,
      calling_ae: "BENCH",
      called_ae: "DIMSE",
      abstract_syntaxes: syntaxes
    )

  result = fun.(assoc)
  Dimse.release(assoc, 5_000)
  result
end

IO.puts("=== End-to-end benchmarks ===")
IO.puts("Listener on port #{port}")
IO.puts("")

Benchee.run(
  %{
    "C-ECHO round trip" => fn ->
      run_with_assoc.(["1.2.840.10008.1.1"], fn assoc ->
        :ok = Dimse.echo(assoc, timeout: 5_000)
      end)
    end,
    "C-STORE 4KB" => fn ->
      run_with_assoc.([ct_uid], fn assoc ->
        :ok = Dimse.store(assoc, ct_uid, "1.2.3.4", data_4kb, timeout: 5_000)
      end)
    end,
    "C-STORE 64KB" => fn ->
      run_with_assoc.([ct_uid], fn assoc ->
        :ok = Dimse.store(assoc, ct_uid, "1.2.3.4", data_64kb, timeout: 5_000)
      end)
    end,
    "C-STORE 1MB" => fn ->
      run_with_assoc.([ct_uid], fn assoc ->
        :ok = Dimse.store(assoc, ct_uid, "1.2.3.4", data_1mb, timeout: 10_000)
      end)
    end
  },
  time: 5,
  warmup: 2,
  memory_time: 0,
  print: [configuration: false]
)

Dimse.stop_listener(ref)
