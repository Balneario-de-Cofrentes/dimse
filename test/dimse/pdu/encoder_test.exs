defmodule Dimse.Pdu.EncoderTest do
  use ExUnit.Case, async: true

  alias Dimse.Pdu
  alias Dimse.Pdu.Encoder

  describe "encode/1 A-RELEASE-RQ" do
    test "encodes to correct 10-byte binary" do
      binary = IO.iodata_to_binary(Encoder.encode(%Pdu.ReleaseRq{}))
      assert binary == <<0x05, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00>>
    end
  end

  describe "encode/1 A-RELEASE-RP" do
    test "encodes to correct 10-byte binary" do
      binary = IO.iodata_to_binary(Encoder.encode(%Pdu.ReleaseRp{}))
      assert binary == <<0x06, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00>>
    end
  end

  describe "encode/1 A-ABORT" do
    test "encodes with source and reason" do
      binary = IO.iodata_to_binary(Encoder.encode(%Pdu.Abort{source: 2, reason: 6}))
      assert binary == <<0x07, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x02, 0x06>>
    end

    test "defaults nil source/reason to 0" do
      binary = IO.iodata_to_binary(Encoder.encode(%Pdu.Abort{source: nil, reason: nil}))
      assert binary == <<0x07, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00>>
    end
  end

  describe "encode/1 A-ASSOCIATE-RJ" do
    test "encodes result, source, and reason" do
      binary =
        IO.iodata_to_binary(Encoder.encode(%Pdu.AssociateRj{result: 1, source: 3, reason: 2}))

      assert binary == <<0x03, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x01, 0x03, 0x02>>
    end
  end

  describe "encode/1 A-ASSOCIATE-RQ" do
    test "starts with PDU type 0x01" do
      rq = %Pdu.AssociateRq{
        protocol_version: 1,
        called_ae_title: "SCP",
        calling_ae_title: "SCU",
        presentation_contexts: [],
        user_information: %Pdu.UserInformation{max_pdu_length: 16_384}
      }

      <<type, _rest::binary>> = IO.iodata_to_binary(Encoder.encode(rq))
      assert type == 0x01
    end

    test "encodes AE titles padded to 16 bytes" do
      rq = %Pdu.AssociateRq{
        called_ae_title: "SCP",
        calling_ae_title: "SCU",
        presentation_contexts: []
      }

      binary = IO.iodata_to_binary(Encoder.encode(rq))
      # Skip: type(1) + reserved(1) + length(4) + protocol_version(2) + reserved(2) = 10 bytes
      <<_header::binary-size(10), called::binary-size(16), calling::binary-size(16),
        _rest::binary>> = binary

      assert called == "SCP             "
      assert calling == "SCU             "
    end

    test "includes presentation context sub-items" do
      rq = %Pdu.AssociateRq{
        called_ae_title: "SCP",
        calling_ae_title: "SCU",
        presentation_contexts: [
          %Pdu.PresentationContext{
            id: 1,
            abstract_syntax: "1.2.840.10008.1.1",
            transfer_syntaxes: ["1.2.840.10008.1.2"]
          }
        ]
      }

      binary = IO.iodata_to_binary(Encoder.encode(rq))
      # Binary must contain the abstract syntax UID
      assert String.contains?(binary, "1.2.840.10008.1.1")
      assert String.contains?(binary, "1.2.840.10008.1.2")
    end
  end

  describe "encode/1 A-ASSOCIATE-AC" do
    test "starts with PDU type 0x02" do
      ac = %Pdu.AssociateAc{
        protocol_version: 1,
        called_ae_title: "SCP",
        calling_ae_title: "SCU",
        presentation_contexts: [],
        user_information: %Pdu.UserInformation{max_pdu_length: 16_384}
      }

      <<type, _rest::binary>> = IO.iodata_to_binary(Encoder.encode(ac))
      assert type == 0x02
    end

    test "encodes accepted presentation contexts with result code" do
      ac = %Pdu.AssociateAc{
        called_ae_title: "SCP",
        calling_ae_title: "SCU",
        presentation_contexts: [
          %Pdu.PresentationContext{
            id: 1,
            result: 0,
            transfer_syntaxes: ["1.2.840.10008.1.2"]
          }
        ]
      }

      binary = IO.iodata_to_binary(Encoder.encode(ac))
      # Must contain AC presentation context item type 0x21
      assert :binary.match(binary, <<0x21>>) != :nomatch
    end
  end

  describe "encode/1 P-DATA-TF" do
    test "encodes a single PDV" do
      pdu = %Pdu.PDataTf{
        pdv_items: [
          %Pdu.PresentationDataValue{
            context_id: 1,
            is_command: true,
            is_last: true,
            data: <<1, 2, 3, 4>>
          }
        ]
      }

      binary = IO.iodata_to_binary(Encoder.encode(pdu))
      # type(1) + reserved(1) + length(4) + pdv_length(4) + ctx(1) + flags(1) + data(4) = 16
      assert byte_size(binary) == 16
      assert <<0x04, 0x00, _length::32, _rest::binary>> = binary
    end

    test "encodes command+last flag as 0x03" do
      pdu = %Pdu.PDataTf{
        pdv_items: [
          %Pdu.PresentationDataValue{
            context_id: 1,
            is_command: true,
            is_last: true,
            data: <<>>
          }
        ]
      }

      binary = IO.iodata_to_binary(Encoder.encode(pdu))
      # Skip header(6) + pdv_length(4) + ctx(1) = 11
      <<_::binary-size(11), flags, _::binary>> = binary
      assert flags == 0x03
    end

    test "encodes data+last flag as 0x02" do
      pdu = %Pdu.PDataTf{
        pdv_items: [
          %Pdu.PresentationDataValue{
            context_id: 1,
            is_command: false,
            is_last: true,
            data: <<>>
          }
        ]
      }

      binary = IO.iodata_to_binary(Encoder.encode(pdu))
      <<_::binary-size(11), flags, _::binary>> = binary
      assert flags == 0x02
    end
  end

  describe "pad_ae/1" do
    test "pads short strings to 16 bytes" do
      assert Encoder.pad_ae("SCP") == "SCP             "
      assert byte_size(Encoder.pad_ae("SCP")) == 16
    end

    test "truncates long strings to 16 bytes" do
      long = String.duplicate("A", 20)
      assert byte_size(Encoder.pad_ae(long)) == 16
    end

    test "returns 16 spaces for empty string" do
      assert Encoder.pad_ae("") == String.duplicate(" ", 16)
    end
  end
end
