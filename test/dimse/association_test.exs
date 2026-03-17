defmodule Dimse.AssociationTest do
  use ExUnit.Case, async: true

  alias Dimse.Association
  alias Dimse.Association.State

  describe "start_link/1" do
    test "starts a GenServer process" do
      assert {:ok, pid} = Association.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "State struct" do
    test "has correct defaults" do
      state = %State{}
      assert state.phase == :idle
      assert state.max_pdu_length == 16_384
      assert state.negotiated_contexts == %{}
      assert state.pdu_buffer == <<>>
      assert state.bytes_received == 0
      assert state.bytes_sent == 0
    end

    test "phase can be set to all valid values" do
      for phase <- [:idle, :negotiating, :established, :releasing, :closed] do
        state = %State{phase: phase}
        assert state.phase == phase
      end
    end
  end
end
