defmodule Dimse.Pdu.DecoderTest do
  use ExUnit.Case, async: true

  alias Dimse.Pdu
  alias Dimse.Pdu.Decoder
  alias Dimse.Test.PduHelpers

  describe "decode/1 incomplete data" do
    test "returns {:incomplete, data} for empty binary" do
      assert {:incomplete, <<>>} = Decoder.decode(<<>>)
    end

    test "returns {:incomplete, data} for partial header (< 6 bytes)" do
      assert {:incomplete, <<0x01, 0x00>>} = Decoder.decode(<<0x01, 0x00>>)
      assert {:incomplete, <<0x01, 0x00, 0x00>>} = Decoder.decode(<<0x01, 0x00, 0x00>>)
    end

    test "returns {:incomplete, data} when payload is shorter than declared length" do
      # Header says 100 bytes but only 4 present
      data = <<0x01, 0x00, 0x00, 0x00, 0x00, 100, "abcd">>
      assert {:incomplete, ^data} = Decoder.decode(data)
    end
  end

  describe "decode/1 A-RELEASE-RQ" do
    test "decodes valid A-RELEASE-RQ" do
      assert {:ok, %Pdu.ReleaseRq{}, <<>>} = Decoder.decode(PduHelpers.release_rq_binary())
    end

    test "returns remaining bytes" do
      binary = PduHelpers.release_rq_binary() <> <<0xFF>>
      assert {:ok, %Pdu.ReleaseRq{}, <<0xFF>>} = Decoder.decode(binary)
    end
  end

  describe "decode/1 A-RELEASE-RP" do
    test "decodes valid A-RELEASE-RP" do
      assert {:ok, %Pdu.ReleaseRp{}, <<>>} = Decoder.decode(PduHelpers.release_rp_binary())
    end
  end

  describe "decode/1 A-ABORT" do
    test "decodes with source and reason" do
      assert {:ok, %Pdu.Abort{source: 2, reason: 6}, <<>>} =
               Decoder.decode(PduHelpers.abort_binary(2, 6))
    end

    test "decodes service-user abort" do
      assert {:ok, %Pdu.Abort{source: 0, reason: 0}, <<>>} =
               Decoder.decode(PduHelpers.abort_binary(0, 0))
    end
  end

  describe "decode/1 A-ASSOCIATE-RJ" do
    test "decodes rejection with result, source, and reason" do
      assert {:ok, %Pdu.AssociateRj{result: 1, source: 1, reason: 1}, <<>>} =
               Decoder.decode(PduHelpers.associate_rj_binary(1, 1, 1))
    end

    test "decodes transient rejection" do
      assert {:ok, %Pdu.AssociateRj{result: 2, source: 1, reason: 2}, <<>>} =
               Decoder.decode(PduHelpers.associate_rj_binary(2, 1, 2))
    end
  end

  describe "decode/1 A-ASSOCIATE-RQ" do
    test "decodes minimal A-ASSOCIATE-RQ" do
      binary = PduHelpers.associate_rq_binary()
      assert {:ok, %Pdu.AssociateRq{} = rq, <<>>} = Decoder.decode(binary)
      assert rq.protocol_version == 1
      assert rq.called_ae_title == "DIMSE"
      assert rq.calling_ae_title == "TEST_SCU"
    end

    test "decodes presentation contexts" do
      binary = PduHelpers.associate_rq_binary()
      {:ok, rq, <<>>} = Decoder.decode(binary)

      assert [%Pdu.PresentationContext{} = pc] = rq.presentation_contexts
      assert pc.id == 1
      assert pc.abstract_syntax == "1.2.840.10008.1.1"
      assert "1.2.840.10008.1.2" in pc.transfer_syntaxes
      assert "1.2.840.10008.1.2.1" in pc.transfer_syntaxes
    end

    test "decodes user information" do
      binary = PduHelpers.associate_rq_binary(max_pdu_length: 32_768)
      {:ok, rq, <<>>} = Decoder.decode(binary)

      assert %Pdu.UserInformation{} = rq.user_information
      assert rq.user_information.max_pdu_length == 32_768
      assert rq.user_information.implementation_uid == "1.2.3.4.5"
      assert rq.user_information.implementation_version == "TEST_0.1"
    end
  end

  describe "decode/1 P-DATA-TF" do
    test "decodes a single command PDV" do
      data = <<0xDE, 0xAD>>

      binary =
        PduHelpers.p_data_binary([
          %{context_id: 1, is_command: true, is_last: true, data: data}
        ])

      assert {:ok, %Pdu.PDataTf{pdv_items: [pdv]}, <<>>} = Decoder.decode(binary)
      assert pdv.context_id == 1
      assert pdv.is_command == true
      assert pdv.is_last == true
      assert pdv.data == data
    end

    test "decodes multiple PDV items" do
      binary =
        PduHelpers.p_data_binary([
          %{context_id: 1, is_command: true, is_last: true, data: <<1, 2>>},
          %{context_id: 1, is_command: false, is_last: true, data: <<3, 4>>}
        ])

      assert {:ok, %Pdu.PDataTf{pdv_items: [pdv1, pdv2]}, <<>>} = Decoder.decode(binary)
      assert pdv1.is_command == true
      assert pdv2.is_command == false
    end

    test "decodes flags correctly" do
      # command=false, last=false -> 0x00
      binary =
        PduHelpers.p_data_binary([
          %{context_id: 1, is_command: false, is_last: false, data: <<0>>}
        ])

      {:ok, %Pdu.PDataTf{pdv_items: [pdv]}, _} = Decoder.decode(binary)
      assert pdv.is_command == false
      assert pdv.is_last == false
    end
  end

  describe "encode/decode roundtrip" do
    alias Dimse.Pdu.Encoder

    test "A-RELEASE-RQ survives roundtrip" do
      original = %Pdu.ReleaseRq{}
      binary = IO.iodata_to_binary(Encoder.encode(original))
      assert {:ok, %Pdu.ReleaseRq{}, <<>>} = Decoder.decode(binary)
    end

    test "A-RELEASE-RP survives roundtrip" do
      original = %Pdu.ReleaseRp{}
      binary = IO.iodata_to_binary(Encoder.encode(original))
      assert {:ok, %Pdu.ReleaseRp{}, <<>>} = Decoder.decode(binary)
    end

    test "A-ABORT survives roundtrip" do
      original = %Pdu.Abort{source: 2, reason: 4}
      binary = IO.iodata_to_binary(Encoder.encode(original))
      assert {:ok, decoded, <<>>} = Decoder.decode(binary)
      assert decoded.source == 2
      assert decoded.reason == 4
    end

    test "A-ASSOCIATE-RJ survives roundtrip" do
      original = %Pdu.AssociateRj{result: 1, source: 3, reason: 2}
      binary = IO.iodata_to_binary(Encoder.encode(original))
      assert {:ok, decoded, <<>>} = Decoder.decode(binary)
      assert decoded.result == 1
      assert decoded.source == 3
      assert decoded.reason == 2
    end

    test "A-ASSOCIATE-RQ survives roundtrip" do
      original = PduHelpers.build_associate_rq()
      binary = IO.iodata_to_binary(Encoder.encode(original))
      assert {:ok, decoded, <<>>} = Decoder.decode(binary)

      assert decoded.protocol_version == original.protocol_version
      assert decoded.called_ae_title == original.called_ae_title
      assert decoded.calling_ae_title == original.calling_ae_title
      assert length(decoded.presentation_contexts) == length(original.presentation_contexts)

      [pc_orig] = original.presentation_contexts
      [pc_dec] = decoded.presentation_contexts
      assert pc_dec.id == pc_orig.id
      assert pc_dec.abstract_syntax == pc_orig.abstract_syntax
      assert pc_dec.transfer_syntaxes == pc_orig.transfer_syntaxes
    end

    test "A-ASSOCIATE-AC survives roundtrip" do
      original = PduHelpers.build_associate_ac()
      binary = IO.iodata_to_binary(Encoder.encode(original))
      assert {:ok, decoded, <<>>} = Decoder.decode(binary)

      assert decoded.protocol_version == original.protocol_version
      [pc_dec] = decoded.presentation_contexts
      assert pc_dec.id == 1
      assert pc_dec.result == 0
    end

    test "P-DATA-TF survives roundtrip" do
      original = %Pdu.PDataTf{
        pdv_items: [
          %Pdu.PresentationDataValue{
            context_id: 1,
            is_command: true,
            is_last: true,
            data: <<1, 2, 3, 4, 5, 6, 7, 8>>
          }
        ]
      }

      binary = IO.iodata_to_binary(Encoder.encode(original))
      assert {:ok, decoded, <<>>} = Decoder.decode(binary)
      assert [pdv] = decoded.pdv_items
      assert pdv.context_id == 1
      assert pdv.is_command == true
      assert pdv.is_last == true
      assert pdv.data == <<1, 2, 3, 4, 5, 6, 7, 8>>
    end

    test "multiple PDUs in a stream decode sequentially" do
      rq_binary = IO.iodata_to_binary(Encoder.encode(%Pdu.ReleaseRq{}))
      rp_binary = IO.iodata_to_binary(Encoder.encode(%Pdu.ReleaseRp{}))
      stream = rq_binary <> rp_binary

      assert {:ok, %Pdu.ReleaseRq{}, rest} = Decoder.decode(stream)
      assert {:ok, %Pdu.ReleaseRp{}, <<>>} = Decoder.decode(rest)
    end
  end
end
