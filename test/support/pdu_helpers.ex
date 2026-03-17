defmodule Dimse.Test.PduHelpers do
  @moduledoc """
  Test helpers for building DICOM PDU binaries and structs.
  """

  alias Dimse.Pdu

  @verification_uid "1.2.840.10008.1.1"
  @implicit_vr_le "1.2.840.10008.1.2"
  @explicit_vr_le "1.2.840.10008.1.2.1"
  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"

  def verification_uid, do: @verification_uid
  def implicit_vr_le, do: @implicit_vr_le
  def explicit_vr_le, do: @explicit_vr_le
  def ct_image_storage, do: @ct_image_storage

  @doc "Builds a minimal A-ASSOCIATE-RQ struct for Verification."
  def build_associate_rq(opts \\ []) do
    %Pdu.AssociateRq{
      protocol_version: 1,
      called_ae_title: Keyword.get(opts, :called_ae, "DIMSE"),
      calling_ae_title: Keyword.get(opts, :calling_ae, "TEST_SCU"),
      presentation_contexts: [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: Keyword.get(opts, :abstract_syntax, @verification_uid),
          transfer_syntaxes:
            Keyword.get(opts, :transfer_syntaxes, [@implicit_vr_le, @explicit_vr_le])
        }
      ],
      user_information: %Pdu.UserInformation{
        max_pdu_length: Keyword.get(opts, :max_pdu_length, 16_384),
        implementation_uid: "1.2.3.4.5",
        implementation_version: "TEST_0.1"
      }
    }
  end

  @doc "Builds a minimal A-ASSOCIATE-AC struct."
  def build_associate_ac(opts \\ []) do
    %Pdu.AssociateAc{
      protocol_version: 1,
      called_ae_title: Keyword.get(opts, :called_ae, "DIMSE"),
      calling_ae_title: Keyword.get(opts, :calling_ae, "TEST_SCU"),
      presentation_contexts: [
        %Pdu.PresentationContext{
          id: 1,
          result: 0,
          transfer_syntaxes: [Keyword.get(opts, :transfer_syntax, @implicit_vr_le)]
        }
      ],
      user_information: %Pdu.UserInformation{
        max_pdu_length: Keyword.get(opts, :max_pdu_length, 16_384),
        implementation_uid: "1.2.3.4.5",
        implementation_version: "TEST_0.1"
      }
    }
  end

  @doc "Builds a C-ECHO-RQ command set."
  def echo_rq_command(message_id \\ 1) do
    %{
      {0x0000, 0x0002} => @verification_uid,
      {0x0000, 0x0100} => 0x0030,
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0800} => 0x0101
    }
  end

  @doc "Builds a C-ECHO-RSP command set."
  def echo_rsp_command(message_id \\ 1) do
    %{
      {0x0000, 0x0002} => @verification_uid,
      {0x0000, 0x0100} => 0x8030,
      {0x0000, 0x0120} => message_id,
      {0x0000, 0x0800} => 0x0101,
      {0x0000, 0x0900} => 0x0000
    }
  end

  @doc "Pads an AE title to exactly 16 bytes (space-padded)."
  def pad_ae(ae) when is_binary(ae) do
    ae |> String.slice(0, 16) |> String.pad_trailing(16)
  end

  @doc "Builds an A-ASSOCIATE-RQ binary with presentation contexts."
  def associate_rq_binary(opts \\ []) do
    rq = build_associate_rq(opts)
    IO.iodata_to_binary(Dimse.Pdu.Encoder.encode(rq))
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

  @doc "Builds an A-ASSOCIATE-RJ binary."
  def associate_rj_binary(result \\ 1, source \\ 1, reason \\ 1) do
    <<0x03, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, result, source, reason>>
  end

  @doc "Builds a P-DATA-TF binary from a list of PDV items."
  def p_data_binary(pdv_items) do
    pdv_data =
      Enum.map(pdv_items, fn %{context_id: ctx, is_command: cmd, is_last: last, data: data} ->
        flags = pdv_flags(cmd, last)
        pdv_length = 2 + byte_size(data)
        <<pdv_length::32, ctx::8, flags::8, data::binary>>
      end)

    payload = IO.iodata_to_binary(pdv_data)
    <<0x04, 0x00, byte_size(payload)::32, payload::binary>>
  end

  defp pdv_flags(true, true), do: 0x03
  defp pdv_flags(true, false), do: 0x01
  defp pdv_flags(false, true), do: 0x02
  defp pdv_flags(false, false), do: 0x00

  @doc "Builds a C-STORE-RQ command set."
  def store_rq_command(sop_class_uid, sop_instance_uid, message_id \\ 1) do
    %{
      {0x0000, 0x0002} => sop_class_uid,
      {0x0000, 0x0100} => 0x0001,
      {0x0000, 0x0110} => message_id,
      {0x0000, 0x0700} => 0x0000,
      {0x0000, 0x0800} => 0x0000,
      {0x0000, 0x1000} => sop_instance_uid
    }
  end

  @doc "Generates a random DICOM-style UID (1.2.xxx.xxx...)."
  def random_uid do
    parts = for _ <- 1..4, do: Integer.to_string(:rand.uniform(99_999))
    "1.2.826.0.1.#{Enum.join(parts, ".")}"
  end

  @doc "Generates a random data set binary of the given size."
  def random_data_set(size \\ 1024) do
    :crypto.strong_rand_bytes(size)
  end

  # --- StreamData generators for property-based tests ---

  @doc "StreamData generator for AE titles (1-16 printable ASCII chars)."
  def gen_ae_title do
    StreamData.string(:alphanumeric, min_length: 1, max_length: 16)
  end

  @doc "StreamData generator for DICOM UIDs (dotted numeric, max 64 chars)."
  def gen_uid do
    StreamData.bind(StreamData.integer(2..6), fn num_parts ->
      parts =
        StreamData.list_of(StreamData.integer(0..99_999), length: num_parts)

      StreamData.map(parts, fn segments ->
        uid = "1.2." <> Enum.join(Enum.map(segments, &Integer.to_string/1), ".")
        String.slice(uid, 0, 64)
      end)
    end)
  end

  @doc "StreamData generator for presentation context IDs (odd, 1-255)."
  def gen_context_id do
    StreamData.map(StreamData.integer(0..127), fn n -> n * 2 + 1 end)
  end

  @doc "StreamData generator for A-ASSOCIATE-RJ PDUs."
  def gen_associate_rj do
    StreamData.fixed_map(%{
      result: StreamData.member_of([1, 2]),
      source: StreamData.integer(1..3),
      reason: StreamData.integer(1..7)
    })
    |> StreamData.map(fn fields ->
      %Pdu.AssociateRj{result: fields.result, source: fields.source, reason: fields.reason}
    end)
  end

  @doc "StreamData generator for A-ABORT PDUs."
  def gen_abort do
    StreamData.fixed_map(%{
      source: StreamData.integer(0..2),
      reason: StreamData.integer(0..6)
    })
    |> StreamData.map(fn fields ->
      %Pdu.Abort{source: fields.source, reason: fields.reason}
    end)
  end

  @doc "StreamData generator for PresentationDataValue items."
  def gen_pdv do
    StreamData.fixed_map(%{
      context_id: gen_context_id(),
      is_command: StreamData.boolean(),
      is_last: StreamData.boolean(),
      data: StreamData.binary(min_length: 0, max_length: 256)
    })
    |> StreamData.map(fn fields ->
      %Pdu.PresentationDataValue{
        context_id: fields.context_id,
        is_command: fields.is_command,
        is_last: fields.is_last,
        data: fields.data
      }
    end)
  end

  @doc "StreamData generator for P-DATA-TF PDUs."
  def gen_p_data_tf do
    StreamData.list_of(gen_pdv(), min_length: 1, max_length: 4)
    |> StreamData.map(fn items -> %Pdu.PDataTf{pdv_items: items} end)
  end

  @doc "StreamData generator for PresentationContext items (RQ-style)."
  def gen_presentation_context do
    StreamData.fixed_map(%{
      id: gen_context_id(),
      abstract_syntax: gen_uid(),
      transfer_syntaxes: StreamData.list_of(gen_uid(), min_length: 1, max_length: 3)
    })
    |> StreamData.map(fn fields ->
      %Pdu.PresentationContext{
        id: fields.id,
        abstract_syntax: fields.abstract_syntax,
        transfer_syntaxes: fields.transfer_syntaxes
      }
    end)
  end

  @doc "StreamData generator for UserInformation items."
  def gen_user_information do
    StreamData.fixed_map(%{
      max_pdu_length: StreamData.integer(4096..65_536),
      implementation_uid: gen_uid(),
      implementation_version: StreamData.string(:alphanumeric, min_length: 1, max_length: 16)
    })
    |> StreamData.map(fn fields ->
      %Pdu.UserInformation{
        max_pdu_length: fields.max_pdu_length,
        implementation_uid: fields.implementation_uid,
        implementation_version: fields.implementation_version
      }
    end)
  end

  @doc "StreamData generator for A-ASSOCIATE-RQ PDUs."
  def gen_associate_rq do
    StreamData.fixed_map(%{
      called_ae: gen_ae_title(),
      calling_ae: gen_ae_title(),
      presentation_contexts:
        StreamData.list_of(gen_presentation_context(), min_length: 1, max_length: 4),
      user_information: gen_user_information()
    })
    |> StreamData.map(fn fields ->
      %Pdu.AssociateRq{
        protocol_version: 1,
        called_ae_title: fields.called_ae,
        calling_ae_title: fields.calling_ae,
        presentation_contexts: fields.presentation_contexts,
        user_information: fields.user_information
      }
    end)
  end

  @doc "StreamData generator for A-ASSOCIATE-AC PDUs."
  def gen_associate_ac do
    StreamData.fixed_map(%{
      called_ae: gen_ae_title(),
      calling_ae: gen_ae_title(),
      presentation_contexts:
        StreamData.list_of(gen_presentation_context_ac(), min_length: 1, max_length: 4),
      user_information: gen_user_information()
    })
    |> StreamData.map(fn fields ->
      %Pdu.AssociateAc{
        protocol_version: 1,
        called_ae_title: fields.called_ae,
        calling_ae_title: fields.calling_ae,
        presentation_contexts: fields.presentation_contexts,
        user_information: fields.user_information
      }
    end)
  end

  @doc "StreamData generator for AC-style PresentationContext items."
  def gen_presentation_context_ac do
    StreamData.fixed_map(%{
      id: gen_context_id(),
      result: StreamData.member_of([0, 1, 2, 3, 4]),
      transfer_syntaxes: StreamData.list_of(gen_uid(), length: 1)
    })
    |> StreamData.map(fn fields ->
      %Pdu.PresentationContext{
        id: fields.id,
        result: fields.result,
        transfer_syntaxes: fields.transfer_syntaxes
      }
    end)
  end
end
