defmodule Dimse.MessageTest do
  use ExUnit.Case, async: true

  alias Dimse.{Command, Message, Pdu}

  describe "Message struct" do
    test "has correct default fields" do
      msg = %Message{}
      assert msg.context_id == nil
      assert msg.command == nil
      assert msg.data == nil
    end

    test "can be constructed with fields" do
      msg = %Message{context_id: 1, command: %{}, data: <<1, 2, 3>>}
      assert msg.context_id == 1
      assert msg.command == %{}
      assert msg.data == <<1, 2, 3>>
    end
  end

  describe "Assembler" do
    test "new/0 creates assembler in command phase" do
      asm = Message.Assembler.new()
      assert asm.phase == :command
      assert asm.context_id == nil
    end

    test "assembles a command-only message (no data set)" do
      # Build a C-ECHO-RQ command
      cmd = %{
        {0x0000, 0x0002} => "1.2.840.10008.1.1",
        {0x0000, 0x0100} => 0x0030,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0101
      }

      {:ok, cmd_binary} = Command.encode(cmd)

      pdv = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: true,
        is_last: true,
        data: cmd_binary
      }

      asm = Message.Assembler.new()
      assert {:complete, message} = Message.Assembler.feed(asm, pdv)
      assert message.context_id == 1
      assert message.command[{0x0000, 0x0100}] == 0x0030
      assert message.data == nil
    end

    test "assembles a message with data set" do
      # Command that says data follows
      cmd = %{
        {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.1.2",
        {0x0000, 0x0100} => 0x0001,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0000
      }

      {:ok, cmd_binary} = Command.encode(cmd)

      cmd_pdv = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: true,
        is_last: true,
        data: cmd_binary
      }

      data_pdv = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: false,
        is_last: true,
        data: <<0xAB, 0xCD, 0xEF>>
      }

      asm = Message.Assembler.new()
      {:continue, asm2} = Message.Assembler.feed(asm, cmd_pdv)
      assert asm2.phase == :data

      {:complete, message} = Message.Assembler.feed(asm2, data_pdv)
      assert message.command[{0x0000, 0x0100}] == 0x0001
      assert message.data == <<0xAB, 0xCD, 0xEF>>
    end

    test "handles multi-fragment command" do
      cmd = %{
        {0x0000, 0x0002} => "1.2.840.10008.1.1",
        {0x0000, 0x0100} => 0x0030,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0101
      }

      {:ok, cmd_binary} = Command.encode(cmd)
      half = div(byte_size(cmd_binary), 2)
      <<first::binary-size(half), second::binary>> = cmd_binary

      pdv1 = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: true,
        is_last: false,
        data: first
      }

      pdv2 = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: true,
        is_last: true,
        data: second
      }

      asm = Message.Assembler.new()
      {:continue, asm2} = Message.Assembler.feed(asm, pdv1)
      {:complete, message} = Message.Assembler.feed(asm2, pdv2)
      assert message.command[{0x0000, 0x0100}] == 0x0030
    end

    test "handles multi-fragment data" do
      cmd = %{
        {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.1.2",
        {0x0000, 0x0100} => 0x0001,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0000
      }

      {:ok, cmd_binary} = Command.encode(cmd)

      cmd_pdv = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: true,
        is_last: true,
        data: cmd_binary
      }

      data_part1 = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: false,
        is_last: false,
        data: <<1, 2, 3>>
      }

      data_part2 = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: false,
        is_last: true,
        data: <<4, 5, 6>>
      }

      asm = Message.Assembler.new()
      {:continue, asm2} = Message.Assembler.feed(asm, cmd_pdv)
      {:continue, asm3} = Message.Assembler.feed(asm2, data_part1)
      {:complete, message} = Message.Assembler.feed(asm3, data_part2)
      assert message.data == <<1, 2, 3, 4, 5, 6>>
    end

    test "returns error for unexpected PDV" do
      asm = Message.Assembler.new()

      # Command phase expects is_command: true, feeding data PDV is unexpected
      data_pdv = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: false,
        is_last: true,
        data: <<>>
      }

      assert {:error, :unexpected_pdv} = Message.Assembler.feed(asm, data_pdv)
    end

    test "returns error when command binary is corrupt" do
      corrupt_pdv = %Pdu.PresentationDataValue{
        context_id: 1,
        is_command: true,
        is_last: true,
        data: <<0x01>>
      }

      asm = Message.Assembler.new()
      assert {:error, {:command_decode_failed, _}} = Message.Assembler.feed(asm, corrupt_pdv)
    end
  end

  describe "fragment/4" do
    test "fragments a command-only message into a single P-DATA-TF" do
      cmd = %{
        {0x0000, 0x0002} => "1.2.840.10008.1.1",
        {0x0000, 0x0100} => 0x0030,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0101
      }

      pdus = Message.fragment(cmd, nil, 1, 16_384)
      # Should produce exactly one P-DATA-TF for the command
      assert [%Pdu.PDataTf{pdv_items: [pdv]}] = pdus
      assert pdv.is_command == true
      assert pdv.is_last == true
      assert pdv.context_id == 1
    end

    test "fragments a message with data into command + data PDUs" do
      cmd = %{
        {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.1.2",
        {0x0000, 0x0100} => 0x0001,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0000
      }

      data = :crypto.strong_rand_bytes(100)
      pdus = Message.fragment(cmd, data, 1, 16_384)

      # At least 2 PDUs: one for command, one for data
      assert length(pdus) >= 2

      # Collect all PDVs
      all_pdvs = Enum.flat_map(pdus, fn pdu -> List.flatten(pdu.pdv_items) end)
      command_pdvs = Enum.filter(all_pdvs, & &1.is_command)
      data_pdvs = Enum.reject(all_pdvs, & &1.is_command)

      assert length(command_pdvs) >= 1
      assert length(data_pdvs) >= 1
      assert List.last(data_pdvs).is_last == true
    end

    test "splits large data across multiple PDUs" do
      cmd = %{
        {0x0000, 0x0002} => "1.2.840.10008.5.1.4.1.1.2",
        {0x0000, 0x0100} => 0x0001,
        {0x0000, 0x0110} => 1,
        {0x0000, 0x0800} => 0x0000
      }

      # Use a very small max_pdu_length to force fragmentation
      data = :crypto.strong_rand_bytes(100)
      pdus = Message.fragment(cmd, data, 1, 50)

      # Collect all PDVs and separate by type
      all_pdvs = Enum.flat_map(pdus, fn pdu -> List.flatten(pdu.pdv_items) end)
      data_pdvs = Enum.reject(all_pdvs, & &1.is_command)

      # Should have multiple data fragments
      assert length(data_pdvs) > 1

      # Last data PDV has is_last: true
      assert List.last(data_pdvs).is_last == true

      # All non-last data PDVs have is_last: false
      non_last = Enum.slice(data_pdvs, 0..-2//1)

      for pdv <- non_last do
        assert pdv.is_last == false
      end

      # Reassembling data should match original
      reassembled = Enum.map_join(data_pdvs, & &1.data)
      assert reassembled == data
    end
  end
end
