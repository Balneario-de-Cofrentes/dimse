defmodule Dimse.Test.PduHelpers do
  @moduledoc """
  Test helpers for building DICOM PDU binaries.

  Provides functions to construct valid PDU binaries for testing the decoder,
  and to build PDU structs for testing the encoder.
  """

  @doc "Builds a minimal valid A-ASSOCIATE-RQ binary."
  def associate_rq_binary(opts \\ []) do
    called_ae = Keyword.get(opts, :called_ae, "REMOTE_SCP") |> pad_ae()
    calling_ae = Keyword.get(opts, :calling_ae, "LOCAL_SCU") |> pad_ae()

    # Minimal A-ASSOCIATE-RQ: protocol version + AE titles + reserved + app context
    application_context = application_context_item()

    payload =
      <<1::16, 0::16>> <>
        called_ae <>
        calling_ae <>
        <<0::256>> <>
        application_context

    <<0x01, 0x00, byte_size(payload)::32>> <> payload
  end

  @doc "Builds an A-RELEASE-RQ binary."
  def release_rq_binary do
    <<0x05, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00>>
  end

  @doc "Builds an A-RELEASE-RP binary."
  def release_rp_binary do
    <<0x06, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00>>
  end

  @doc "Builds an A-ABORT binary."
  def abort_binary(source \\ 0, reason \\ 0) do
    <<0x07, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, source, reason>>
  end

  @doc "Pads an AE title to exactly 16 bytes (space-padded)."
  def pad_ae(ae) when is_binary(ae) do
    String.pad_trailing(ae, 16)
  end

  defp application_context_item do
    uid = "1.2.840.10008.3.1.1.1"
    <<0x10, 0x00, byte_size(uid)::16>> <> uid
  end
end
