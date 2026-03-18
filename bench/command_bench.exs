alias Dimse.Command

# --- Test data: typical DIMSE command sets ---

echo_rq = %{
  {0x0000, 0x0002} => "1.2.840.10008.1.1",
  {0x0000, 0x0100} => 0x0030,
  {0x0000, 0x0110} => 1,
  {0x0000, 0x0800} => 0x0101
}

store_rq = %{
  {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.1.2",
  {0x0000, 0x0100} => 0x0001,
  {0x0000, 0x0110} => 42,
  {0x0000, 0x0700} => 0x0000,
  {0x0000, 0x0800} => 0x0000,
  {0x0000, 0x1000} => "1.2.826.0.1.3680043.8.498.12345678.12345678901.1"
}

_find_rsp = %{
  {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.2.2.1",
  {0x0000, 0x0100} => 0x8020,
  {0x0000, 0x0120} => 1,
  {0x0000, 0x0800} => 0x0000,
  {0x0000, 0x0900} => 0xFF00
}

move_rq = %{
  {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.2.2.2",
  {0x0000, 0x0100} => 0x0021,
  {0x0000, 0x0110} => 7,
  {0x0000, 0x0600} => "DEST_SCP",
  {0x0000, 0x0700} => 0x0000,
  {0x0000, 0x0800} => 0x0000
}

# Pre-encode for decode benchmarks
{:ok, echo_binary} = Command.encode(echo_rq)
{:ok, store_binary} = Command.encode(store_rq)
{:ok, move_binary} = Command.encode(move_rq)

IO.puts("=== Command set sizes ===")
IO.puts("C-ECHO-RQ:  #{byte_size(echo_binary)} bytes")
IO.puts("C-STORE-RQ: #{byte_size(store_binary)} bytes")
IO.puts("C-MOVE-RQ:  #{byte_size(move_binary)} bytes")
IO.puts("")

Benchee.run(
  %{
    "encode C-ECHO-RQ (4 tags)" => fn -> Command.encode(echo_rq) end,
    "encode C-STORE-RQ (6 tags)" => fn -> Command.encode(store_rq) end,
    "encode C-MOVE-RQ (6 tags)" => fn -> Command.encode(move_rq) end,
    "decode C-ECHO-RQ" => fn -> Command.decode(echo_binary) end,
    "decode C-STORE-RQ" => fn -> Command.decode(store_binary) end,
    "decode C-MOVE-RQ" => fn -> Command.decode(move_binary) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [configuration: false]
)
