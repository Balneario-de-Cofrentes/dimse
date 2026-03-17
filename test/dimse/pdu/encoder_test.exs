defmodule Dimse.Pdu.EncoderTest do
  use ExUnit.Case, async: true

  alias Dimse.Pdu.Encoder

  describe "encode/1" do
    test "raises for now" do
      assert_raise RuntimeError, "not implemented", fn ->
        Encoder.encode(%Dimse.Pdu.ReleaseRq{})
      end
    end
  end

  # TODO: Implement these tests when encoder is built
  #
  # describe "encode/1 roundtrip" do
  #   test "A-RELEASE-RQ encodes to correct binary" do
  #     iodata = Encoder.encode(%Dimse.Pdu.ReleaseRq{})
  #     assert IO.iodata_to_binary(iodata) ==
  #            <<0x05, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00>>
  #   end
  # end
end
