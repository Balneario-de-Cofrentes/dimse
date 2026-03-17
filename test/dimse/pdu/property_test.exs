defmodule Dimse.Pdu.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Dimse.Pdu.{Encoder, Decoder}
  alias Dimse.Test.PduHelpers

  @moduletag :property

  describe "encode/decode roundtrip" do
    property "A-ASSOCIATE-RJ survives roundtrip" do
      check all(pdu <- PduHelpers.gen_associate_rj()) do
        binary = IO.iodata_to_binary(Encoder.encode(pdu))
        assert {:ok, decoded, <<>>} = Decoder.decode(binary)
        assert decoded.result == pdu.result
        assert decoded.source == pdu.source
        assert decoded.reason == pdu.reason
      end
    end

    property "A-ABORT survives roundtrip" do
      check all(pdu <- PduHelpers.gen_abort()) do
        binary = IO.iodata_to_binary(Encoder.encode(pdu))
        assert {:ok, decoded, <<>>} = Decoder.decode(binary)
        assert decoded.source == pdu.source
        assert decoded.reason == pdu.reason
      end
    end

    property "P-DATA-TF survives roundtrip" do
      check all(pdu <- PduHelpers.gen_p_data_tf()) do
        binary = IO.iodata_to_binary(Encoder.encode(pdu))
        assert {:ok, decoded, <<>>} = Decoder.decode(binary)
        assert length(decoded.pdv_items) == length(pdu.pdv_items)

        Enum.zip(pdu.pdv_items, decoded.pdv_items)
        |> Enum.each(fn {orig, dec} ->
          assert dec.context_id == orig.context_id
          assert dec.is_command == orig.is_command
          assert dec.is_last == orig.is_last
          assert dec.data == orig.data
        end)
      end
    end

    property "A-ASSOCIATE-RQ survives roundtrip" do
      check all(pdu <- PduHelpers.gen_associate_rq()) do
        binary = IO.iodata_to_binary(Encoder.encode(pdu))
        assert {:ok, decoded, <<>>} = Decoder.decode(binary)

        # AE titles are space-padded/trimmed in roundtrip
        assert decoded.called_ae_title == String.trim(pdu.called_ae_title)
        assert decoded.calling_ae_title == String.trim(pdu.calling_ae_title)
        assert decoded.protocol_version == pdu.protocol_version
        assert length(decoded.presentation_contexts) == length(pdu.presentation_contexts)

        Enum.zip(pdu.presentation_contexts, decoded.presentation_contexts)
        |> Enum.each(fn {orig, dec} ->
          assert dec.id == orig.id
          assert dec.abstract_syntax == orig.abstract_syntax
          assert dec.transfer_syntaxes == orig.transfer_syntaxes
        end)

        assert decoded.user_information.max_pdu_length == pdu.user_information.max_pdu_length

        assert decoded.user_information.implementation_uid ==
                 pdu.user_information.implementation_uid

        assert decoded.user_information.implementation_version ==
                 pdu.user_information.implementation_version
      end
    end

    property "A-ASSOCIATE-AC survives roundtrip" do
      check all(pdu <- PduHelpers.gen_associate_ac()) do
        binary = IO.iodata_to_binary(Encoder.encode(pdu))
        assert {:ok, decoded, <<>>} = Decoder.decode(binary)

        assert decoded.called_ae_title == String.trim(pdu.called_ae_title)
        assert decoded.calling_ae_title == String.trim(pdu.calling_ae_title)
        assert decoded.protocol_version == pdu.protocol_version
        assert length(decoded.presentation_contexts) == length(pdu.presentation_contexts)

        Enum.zip(pdu.presentation_contexts, decoded.presentation_contexts)
        |> Enum.each(fn {orig, dec} ->
          assert dec.id == orig.id
          assert dec.result == orig.result
          assert dec.transfer_syntaxes == orig.transfer_syntaxes
        end)
      end
    end

    property "A-RELEASE-RQ survives roundtrip" do
      check all(_ <- StreamData.constant(nil)) do
        pdu = %Dimse.Pdu.ReleaseRq{}
        binary = IO.iodata_to_binary(Encoder.encode(pdu))
        assert {:ok, %Dimse.Pdu.ReleaseRq{}, <<>>} = Decoder.decode(binary)
      end
    end

    property "A-RELEASE-RP survives roundtrip" do
      check all(_ <- StreamData.constant(nil)) do
        pdu = %Dimse.Pdu.ReleaseRp{}
        binary = IO.iodata_to_binary(Encoder.encode(pdu))
        assert {:ok, %Dimse.Pdu.ReleaseRp{}, <<>>} = Decoder.decode(binary)
      end
    end
  end

  describe "incomplete data handling" do
    property "truncated PDU returns :incomplete" do
      check all(pdu <- PduHelpers.gen_p_data_tf()) do
        binary = IO.iodata_to_binary(Encoder.encode(pdu))

        if byte_size(binary) > 6 do
          # Truncate somewhere after the header
          truncate_at = :rand.uniform(byte_size(binary) - 1)
          truncated = binary_part(binary, 0, truncate_at)
          assert {:incomplete, ^truncated} = Decoder.decode(truncated)
        end
      end
    end
  end

  describe "concatenated PDUs" do
    property "decoder returns remaining bytes from concatenated PDUs" do
      check all(
              pdu1 <- PduHelpers.gen_abort(),
              pdu2 <- PduHelpers.gen_associate_rj()
            ) do
        bin1 = IO.iodata_to_binary(Encoder.encode(pdu1))
        bin2 = IO.iodata_to_binary(Encoder.encode(pdu2))
        combined = bin1 <> bin2

        assert {:ok, decoded1, rest} = Decoder.decode(combined)
        assert decoded1.source == pdu1.source
        assert rest == bin2

        assert {:ok, decoded2, <<>>} = Decoder.decode(rest)
        assert decoded2.result == pdu2.result
      end
    end
  end

  describe "command set roundtrip" do
    property "encode/decode preserves command set values" do
      check all(
              sop_class <- PduHelpers.gen_uid(),
              message_id <- StreamData.integer(1..65_535),
              status <- StreamData.member_of([0x0000, 0x0001, 0xFF00, 0xC000])
            ) do
        command = %{
          {0x0000, 0x0002} => sop_class,
          {0x0000, 0x0100} => 0x0030,
          {0x0000, 0x0110} => message_id,
          {0x0000, 0x0800} => 0x0101,
          {0x0000, 0x0900} => status
        }

        assert {:ok, encoded} = Dimse.Command.encode(command)
        assert {:ok, decoded} = Dimse.Command.decode(encoded)

        # UID may get null-padded to even length, then trimmed on decode
        assert decoded[{0x0000, 0x0002}] == sop_class
        assert decoded[{0x0000, 0x0100}] == 0x0030
        assert decoded[{0x0000, 0x0110}] == message_id
        assert decoded[{0x0000, 0x0800}] == 0x0101
        assert decoded[{0x0000, 0x0900}] == status
      end
    end
  end
end
