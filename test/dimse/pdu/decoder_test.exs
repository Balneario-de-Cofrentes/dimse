defmodule Dimse.Pdu.DecoderTest do
  use ExUnit.Case, async: true

  alias Dimse.Pdu.Decoder

  describe "decode/1" do
    test "returns {:error, :not_implemented} for now" do
      assert {:error, :not_implemented} = Decoder.decode(<<>>)
    end
  end

  # TODO: Implement these tests when decoder is built
  #
  # describe "decode/1 with A-RELEASE-RQ" do
  #   test "decodes a valid A-RELEASE-RQ binary" do
  #     binary = Dimse.Test.PduHelpers.release_rq_binary()
  #     assert {:ok, %Dimse.Pdu.ReleaseRq{}, <<>>} = Decoder.decode(binary)
  #   end
  # end
  #
  # describe "decode/1 with A-RELEASE-RP" do
  #   test "decodes a valid A-RELEASE-RP binary" do
  #     binary = Dimse.Test.PduHelpers.release_rp_binary()
  #     assert {:ok, %Dimse.Pdu.ReleaseRp{}, <<>>} = Decoder.decode(binary)
  #   end
  # end
  #
  # describe "decode/1 with A-ABORT" do
  #   test "decodes a valid A-ABORT binary" do
  #     binary = Dimse.Test.PduHelpers.abort_binary(2, 0)
  #     assert {:ok, %Dimse.Pdu.Abort{source: 2, reason: 0}, <<>>} = Decoder.decode(binary)
  #   end
  # end
  #
  # describe "decode/1 with incomplete data" do
  #   test "returns {:incomplete, data} for partial header" do
  #     assert {:incomplete, <<0x01, 0x00>>} = Decoder.decode(<<0x01, 0x00>>)
  #   end
  # end
end
