defmodule Dimse.PduTest do
  use ExUnit.Case, async: true

  alias Dimse.Pdu

  describe "PDU structs" do
    test "AssociateRq struct has expected fields" do
      rq = %Pdu.AssociateRq{}
      assert Map.has_key?(rq, :protocol_version)
      assert Map.has_key?(rq, :called_ae_title)
      assert Map.has_key?(rq, :calling_ae_title)
      assert Map.has_key?(rq, :application_context)
      assert Map.has_key?(rq, :presentation_contexts)
      assert Map.has_key?(rq, :user_information)
    end

    test "AssociateAc struct has expected fields" do
      ac = %Pdu.AssociateAc{}
      assert Map.has_key?(ac, :protocol_version)
      assert Map.has_key?(ac, :presentation_contexts)
    end

    test "AssociateRj struct has expected fields" do
      rj = %Pdu.AssociateRj{}
      assert Map.has_key?(rj, :result)
      assert Map.has_key?(rj, :source)
      assert Map.has_key?(rj, :reason)
    end

    test "PDataTf struct has pdv_items field" do
      pdu = %Pdu.PDataTf{}
      assert Map.has_key?(pdu, :pdv_items)
    end

    test "PresentationDataValue struct has expected fields" do
      pdv = %Pdu.PresentationDataValue{}
      assert Map.has_key?(pdv, :context_id)
      assert Map.has_key?(pdv, :is_command)
      assert Map.has_key?(pdv, :is_last)
      assert Map.has_key?(pdv, :data)
    end

    test "ReleaseRq and ReleaseRp are empty structs" do
      assert %Pdu.ReleaseRq{} == %Pdu.ReleaseRq{}
      assert %Pdu.ReleaseRp{} == %Pdu.ReleaseRp{}
    end

    test "Abort struct has source and reason" do
      abort = %Pdu.Abort{source: 2, reason: 0}
      assert abort.source == 2
      assert abort.reason == 0
    end

    test "PresentationContext struct has expected fields" do
      pc = %Pdu.PresentationContext{id: 1, abstract_syntax: "1.2.3", transfer_syntaxes: ["1.2.4"]}
      assert pc.id == 1
      assert pc.abstract_syntax == "1.2.3"
    end

    test "UserInformation struct has expected fields" do
      ui = %Pdu.UserInformation{max_pdu_length: 16_384}
      assert ui.max_pdu_length == 16_384
    end
  end
end
