defmodule Dimse.AssociationTest do
  use ExUnit.Case, async: true

  alias Dimse.Association
  alias Dimse.Association.{State, Config}

  @verification_uid "1.2.840.10008.1.1"
  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"

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

    test "returns :no_accepted_context when no negotiated presentation context matches" do
      {:ok, ref} = Dimse.start_listener(port: 0, handler: Dimse.Scp.Echo)
      port = :ranch.get_port(ref)

      {:ok, assoc} =
        Dimse.connect("127.0.0.1", port,
          calling_ae: "TEST_SCU",
          called_ae: "DIMSE",
          abstract_syntaxes: [@verification_uid]
        )

      assert :ok = wait_for_established(assoc)

      assert {:error, :no_accepted_context} =
               Dimse.store(assoc, @ct_image_storage, "1.2.3", <<1, 2, 3>>, timeout: 1_000)

      assert :ok = Dimse.release(assoc, 5_000)
      Dimse.stop_listener(ref)
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
      assert state.proposed_contexts == %{}
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

  defp wait_for_established(assoc, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_established(assoc, deadline)
  end

  defp do_wait_for_established(assoc, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      flunk("Association did not reach :established within timeout")
    end

    contexts = Dimse.Association.negotiated_contexts(assoc)

    if map_size(contexts) > 0 do
      :ok
    else
      Process.sleep(10)
      do_wait_for_established(assoc, deadline)
    end
  end
end
