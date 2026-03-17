defmodule Dimse.AssociationTest do
  use ExUnit.Case, async: true

  alias Dimse.Association
  alias Dimse.Association.{State, Config}

  describe "start_link/1" do
    test "starts a GenServer process in idle phase" do
      assert {:ok, pid} = Association.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "accepts custom config" do
      config = %Config{ae_title: "MY_SCP", max_pdu_length: 32_768}
      assert {:ok, pid} = Association.start_link(config: config, ae_title: "MY_SCP")
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "request/4 when not established" do
    test "returns error when association is in idle phase" do
      {:ok, pid} = Association.start_link([])
      assert {:error, :not_established} = Association.request(pid, %{}, nil, 1_000)
      GenServer.stop(pid)
    end
  end

  describe "release/2 when not established" do
    test "returns error when association is in idle phase" do
      {:ok, pid} = Association.start_link([])
      assert {:error, :not_established} = Association.release(pid, 1_000)
      GenServer.stop(pid)
    end
  end

  describe "negotiated_contexts/1" do
    test "returns empty map for new association" do
      {:ok, pid} = Association.start_link([])
      assert %{} = Association.negotiated_contexts(pid)
      GenServer.stop(pid)
    end
  end

  describe "abort/1" do
    test "stops the association process" do
      # Use start (not start_link) to avoid exit propagation
      {:ok, pid} = Association.start([])
      ref = Process.monitor(pid)
      Association.abort(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
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
      assert state.pending_request == nil
      assert state.pending_release == nil
      assert state.artim_timer == nil
    end

    test "phase can be set to all valid values" do
      for phase <- [:idle, :negotiating, :established, :releasing, :closed] do
        state = %State{phase: phase}
        assert state.phase == phase
      end
    end
  end

  describe "Config struct" do
    test "has correct defaults" do
      config = %Config{}
      assert config.ae_title == "DIMSE"
      assert config.max_pdu_length == 16_384
      assert config.max_associations == 200
      assert config.association_timeout == 600_000
      assert config.dimse_timeout == 30_000
      assert config.artim_timeout == 30_000
      assert config.num_acceptors == 10
    end
  end
end
