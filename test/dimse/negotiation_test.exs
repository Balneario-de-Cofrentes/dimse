defmodule Dimse.Association.NegotiationTest do
  use ExUnit.Case, async: true

  alias Dimse.Association.Negotiation
  alias Dimse.Pdu

  @verification_uid "1.2.840.10008.1.1"
  @ct_storage_uid "1.2.840.10008.5.1.4.1.1.2"
  @implicit_vr_le "1.2.840.10008.1.2"
  @explicit_vr_le "1.2.840.10008.1.2.1"

  describe "negotiate/3" do
    test "accepts matching abstract syntax and transfer syntax" do
      proposed = [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: @verification_uid,
          transfer_syntaxes: [@implicit_vr_le]
        }
      ]

      supported_as = MapSet.new([@verification_uid])
      supported_ts = MapSet.new([@implicit_vr_le])

      {results, accepted_map} = Negotiation.negotiate(proposed, supported_as, supported_ts)

      assert [%Pdu.PresentationContext{id: 1, result: 0}] = results
      assert accepted_map[1] == {@verification_uid, @implicit_vr_le}
    end

    test "rejects unsupported abstract syntax" do
      proposed = [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: @ct_storage_uid,
          transfer_syntaxes: [@implicit_vr_le]
        }
      ]

      supported_as = MapSet.new([@verification_uid])
      supported_ts = MapSet.new([@implicit_vr_le])

      {results, accepted_map} = Negotiation.negotiate(proposed, supported_as, supported_ts)

      assert [%Pdu.PresentationContext{id: 1, result: 3}] = results
      assert accepted_map == %{}
    end

    test "rejects when no transfer syntax matches" do
      proposed = [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: @verification_uid,
          transfer_syntaxes: ["1.2.840.10008.1.2.4.50"]
        }
      ]

      supported_as = MapSet.new([@verification_uid])
      supported_ts = MapSet.new([@implicit_vr_le])

      {results, accepted_map} = Negotiation.negotiate(proposed, supported_as, supported_ts)

      assert [%Pdu.PresentationContext{id: 1, result: 4}] = results
      assert accepted_map == %{}
    end

    test "selects first matching transfer syntax" do
      proposed = [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: @verification_uid,
          transfer_syntaxes: ["1.2.840.10008.1.2.4.50", @explicit_vr_le, @implicit_vr_le]
        }
      ]

      supported_as = MapSet.new([@verification_uid])
      supported_ts = MapSet.new([@implicit_vr_le, @explicit_vr_le])

      {results, accepted_map} = Negotiation.negotiate(proposed, supported_as, supported_ts)

      assert [%Pdu.PresentationContext{id: 1, result: 0}] = results
      # Should select explicit VR LE since it appears first in the proposed list
      # after filtering out unsupported ones
      {_, selected_ts} = accepted_map[1]
      assert selected_ts == @explicit_vr_le
    end

    test "handles multiple presentation contexts" do
      proposed = [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: @verification_uid,
          transfer_syntaxes: [@implicit_vr_le]
        },
        %Pdu.PresentationContext{
          id: 3,
          abstract_syntax: @ct_storage_uid,
          transfer_syntaxes: [@implicit_vr_le]
        },
        %Pdu.PresentationContext{
          id: 5,
          abstract_syntax: "1.2.840.10008.5.1.4.1.1.7",
          transfer_syntaxes: [@explicit_vr_le]
        }
      ]

      supported_as = MapSet.new([@verification_uid, @ct_storage_uid])
      supported_ts = MapSet.new([@implicit_vr_le, @explicit_vr_le])

      {results, accepted_map} = Negotiation.negotiate(proposed, supported_as, supported_ts)

      assert length(results) == 3

      # Context 1: accepted (verification)
      assert Enum.find(results, &(&1.id == 1)).result == 0

      # Context 3: accepted (CT Storage)
      assert Enum.find(results, &(&1.id == 3)).result == 0

      # Context 5: rejected (abstract syntax not supported)
      assert Enum.find(results, &(&1.id == 5)).result == 3

      assert map_size(accepted_map) == 2
      assert accepted_map[1] != nil
      assert accepted_map[3] != nil
      assert accepted_map[5] == nil
    end

    test "returns empty accepted map when nothing matches" do
      proposed = [
        %Pdu.PresentationContext{
          id: 1,
          abstract_syntax: "1.2.3.4.5",
          transfer_syntaxes: ["1.2.3.4.6"]
        }
      ]

      {_results, accepted_map} =
        Negotiation.negotiate(
          proposed,
          MapSet.new([@verification_uid]),
          MapSet.new([@implicit_vr_le])
        )

      assert accepted_map == %{}
    end
  end
end
