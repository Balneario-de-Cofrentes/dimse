alias Dimse.Message

# --- Test data ---

echo_command = %{
  {0x0000, 0x0002} => "1.2.840.10008.1.1",
  {0x0000, 0x0100} => 0x0030,
  {0x0000, 0x0110} => 1,
  {0x0000, 0x0800} => 0x0101
}

store_command = %{
  {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.1.2",
  {0x0000, 0x0100} => 0x0001,
  {0x0000, 0x0110} => 42,
  {0x0000, 0x0700} => 0x0000,
  {0x0000, 0x0800} => 0x0000,
  {0x0000, 0x1000} => "1.2.826.0.1.3680043.8.498.12345678.12345678901.1"
}

# Various data sizes
data_1kb = :crypto.strong_rand_bytes(1024)
data_64kb = :crypto.strong_rand_bytes(65_536)
data_1mb = :crypto.strong_rand_bytes(1_048_576)

max_pdu = 16_384

IO.puts("=== Message fragmentation ===")
IO.puts("1 KB data  -> #{length(Message.fragment(store_command, data_1kb, 1, max_pdu))} PDUs")
IO.puts("64 KB data -> #{length(Message.fragment(store_command, data_64kb, 1, max_pdu))} PDUs")
IO.puts("1 MB data  -> #{length(Message.fragment(store_command, data_1mb, 1, max_pdu))} PDUs")
IO.puts("")

# Pre-fragment for assembly benchmark
pdus_1kb = Message.fragment(store_command, data_1kb, 1, max_pdu)
pdus_64kb = Message.fragment(store_command, data_64kb, 1, max_pdu)

# Extract all PDV items for assembly benchmark
pdvs_1kb = Enum.flat_map(pdus_1kb, & &1.pdv_items)
pdvs_64kb = Enum.flat_map(pdus_64kb, & &1.pdv_items)

assemble = fn pdvs ->
  Enum.reduce(pdvs, Message.Assembler.new(), fn pdv, asm ->
    case Message.Assembler.feed(asm, pdv) do
      {:continue, new_asm} -> new_asm
      {:complete, _msg} -> Message.Assembler.new()
    end
  end)
end

Benchee.run(
  %{
    "fragment echo (no data)" => fn -> Message.fragment(echo_command, nil, 1, max_pdu) end,
    "fragment store 1KB" => fn -> Message.fragment(store_command, data_1kb, 1, max_pdu) end,
    "fragment store 64KB" => fn -> Message.fragment(store_command, data_64kb, 1, max_pdu) end,
    "fragment store 1MB" => fn -> Message.fragment(store_command, data_1mb, 1, max_pdu) end,
    "assemble 1KB (#{length(pdvs_1kb)} PDVs)" => fn -> assemble.(pdvs_1kb) end,
    "assemble 64KB (#{length(pdvs_64kb)} PDVs)" => fn -> assemble.(pdvs_64kb) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [configuration: false]
)
