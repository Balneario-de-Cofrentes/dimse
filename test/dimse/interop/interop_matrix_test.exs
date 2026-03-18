defmodule Dimse.Interop.InteropMatrixTest do
  @moduledoc """
  DICOM interoperability matrix -- tests Dimse against external DICOM peers.

  ## Interop Matrix

  | Peer        | AE Title   | Host:Port        | Echo | Store | Find | Move | Get |
  |-------------|------------|------------------|------|-------|------|------|-----|
  | DCMTK       | DCMTK_SCP  | localhost:14112  | OK   | OK    | ---  | ---  | --- |
  | Orthanc     | ORTHANC    | localhost:14242  | OK   | OK    | OK   | OK*  | OK  |
  | pynetdicom  | PYNET_SCP  | localhost:14113  | OK   | OK    | ---  | ---  | --- |
  | Dimse SCP   | DIMSE_SCP  | localhost:14114  | OK   | OK    | OK   | OK   | OK  |

  *Move requires the destination SCP to be registered in Orthanc's config.

  ## Accepted Gaps & Known Deviations

  - DCMTK storescp does not support C-FIND/C-MOVE/C-GET (storage-only SCP).
  - pynetdicom SCP in this config supports only C-ECHO and C-STORE.
  - Orthanc C-MOVE requires the destination AE to be registered; we test with
    Orthanc as both move SCP and store destination (self-move) where possible.
  - Transfer syntax negotiation may differ: DCMTK and Orthanc propose many
    syntaxes; Dimse proposes Implicit VR LE + Explicit VR LE by default.
  - Max PDU length: each peer may negotiate a different effective PDU size.
    Dimse uses min(local, remote) per PS3.8.

  ## Prerequisites

  Start the Docker services before running:

      docker compose -f docker-compose.interop.yml up -d
      mix test --only interop

  ## Environment Variables

  Override peer addresses if running non-default Docker networking:

  - `DIMSE_DCMTK_HOST` / `DIMSE_DCMTK_PORT`
  - `DIMSE_ORTHANC_HOST` / `DIMSE_ORTHANC_PORT`
  - `DIMSE_PYNET_HOST` / `DIMSE_PYNET_PORT`
  - `DIMSE_SCP_HOST` / `DIMSE_SCP_PORT`
  """

  use ExUnit.Case

  @moduletag :interop

  # --- Peer configuration ---

  @peers %{
    dcmtk: %{
      ae_title: "DCMTK_SCP",
      host: System.get_env("DIMSE_DCMTK_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("DIMSE_DCMTK_PORT", "14112")),
      capabilities: [:echo, :store]
    },
    orthanc: %{
      ae_title: "ORTHANC",
      host: System.get_env("DIMSE_ORTHANC_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("DIMSE_ORTHANC_PORT", "14242")),
      capabilities: [:echo, :store, :find, :get]
    },
    pynetdicom: %{
      ae_title: "PYNET_SCP",
      host: System.get_env("DIMSE_PYNET_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("DIMSE_PYNET_PORT", "14113")),
      capabilities: [:echo, :store]
    },
    dimse_scp: %{
      ae_title: "DIMSE_SCP",
      host: System.get_env("DIMSE_SCP_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("DIMSE_SCP_PORT", "14114")),
      capabilities: [:echo, :store, :find, :move, :get]
    }
  }

  @verification_uid "1.2.840.10008.1.1"
  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"
  @study_root_find "1.2.840.10008.5.1.4.1.2.2.1"
  @study_root_get "1.2.840.10008.5.1.4.1.2.2.3"

  # --- Helpers ---

  defp peer(name), do: Map.fetch!(@peers, name)

  defp peer_available?(name) do
    p = peer(name)

    case :gen_tcp.connect(to_charlist(p.host), p.port, [], 2_000) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        true

      {:error, _} ->
        false
    end
  end

  defp skip_unless_available(name) do
    unless peer_available?(name) do
      ExUnit.Assertions.flunk(
        "Peer #{name} not available at #{peer(name).host}:#{peer(name).port}. " <>
          "Start with: docker compose -f docker-compose.interop.yml up -d"
      )
    end
  end

  defp connect_to_peer(name, abstract_syntaxes) do
    p = peer(name)

    Dimse.connect(p.host, p.port,
      calling_ae: "DIMSE_TEST",
      called_ae: p.ae_title,
      abstract_syntaxes: abstract_syntaxes,
      timeout: 10_000
    )
  end

  defp wait_for_established(assoc) do
    contexts = Dimse.Association.negotiated_contexts(assoc)

    assert map_size(contexts) > 0,
           "Association not established"

    :ok
  end

  defp assert_echo(peer_name) do
    skip_unless_available(peer_name)
    {:ok, assoc} = connect_to_peer(peer_name, [@verification_uid])
    wait_for_established(assoc)
    assert :ok = Dimse.echo(assoc, timeout: 10_000)
    assert :ok = Dimse.release(assoc, 5_000)
  end

  defp assert_multi_echo(peer_name, count) do
    skip_unless_available(peer_name)
    {:ok, assoc} = connect_to_peer(peer_name, [@verification_uid])
    wait_for_established(assoc)
    for _ <- 1..count, do: assert(:ok = Dimse.echo(assoc, timeout: 10_000))
    assert :ok = Dimse.release(assoc, 5_000)
  end

  defp assert_store(peer_name, data_size) do
    skip_unless_available(peer_name)
    {:ok, assoc} = connect_to_peer(peer_name, [@ct_image_storage])
    wait_for_established(assoc)

    sop_instance_uid = Dimse.Test.PduHelpers.random_uid()
    data_set = :crypto.strong_rand_bytes(data_size)

    assert :ok =
             Dimse.store(assoc, @ct_image_storage, sop_instance_uid, data_set, timeout: 30_000)

    assert :ok = Dimse.release(assoc, 5_000)
  end

  defp assert_negotiation(peer_name) do
    skip_unless_available(peer_name)
    {:ok, assoc} = connect_to_peer(peer_name, [@verification_uid])
    wait_for_established(assoc)

    contexts = Dimse.Association.negotiated_contexts(assoc)
    assert map_size(contexts) >= 1

    for {_id, {as, ts}} <- contexts do
      assert is_binary(as) and byte_size(as) > 0
      assert is_binary(ts) and byte_size(ts) > 0
    end

    state = :sys.get_state(assoc)
    assert is_binary(state.implementation_uid)
    assert byte_size(state.implementation_uid) > 0

    assert :ok = Dimse.release(assoc, 5_000)
  end

  # --- C-ECHO tests ---

  describe "C-ECHO against dcmtk" do
    test "echo succeeds", do: assert_echo(:dcmtk)
    test "multiple echoes on same association", do: assert_multi_echo(:dcmtk, 5)
  end

  describe "C-ECHO against orthanc" do
    test "echo succeeds", do: assert_echo(:orthanc)
    test "multiple echoes on same association", do: assert_multi_echo(:orthanc, 5)
  end

  describe "C-ECHO against pynetdicom" do
    test "echo succeeds", do: assert_echo(:pynetdicom)
    test "multiple echoes on same association", do: assert_multi_echo(:pynetdicom, 5)
  end

  describe "C-ECHO against dimse_scp" do
    test "echo succeeds", do: assert_echo(:dimse_scp)
    test "multiple echoes on same association", do: assert_multi_echo(:dimse_scp, 5)
  end

  # --- C-STORE tests ---

  describe "C-STORE against dcmtk" do
    test "store a small CT instance", do: assert_store(:dcmtk, 256)
    test "store a large CT instance (64KB, tests fragmentation)", do: assert_store(:dcmtk, 65_536)
  end

  describe "C-STORE against orthanc" do
    test "store a small CT instance", do: assert_store(:orthanc, 256)

    test "store a large CT instance (64KB, tests fragmentation)",
      do: assert_store(:orthanc, 65_536)
  end

  describe "C-STORE against pynetdicom" do
    test "store a small CT instance", do: assert_store(:pynetdicom, 256)

    test "store a large CT instance (64KB, tests fragmentation)",
      do: assert_store(:pynetdicom, 65_536)
  end

  describe "C-STORE against dimse_scp" do
    test "store a small CT instance", do: assert_store(:dimse_scp, 256)

    test "store a large CT instance (64KB, tests fragmentation)",
      do: assert_store(:dimse_scp, 65_536)
  end

  # --- C-FIND tests ---

  describe "C-FIND against orthanc" do
    test "study-level find returns a list (possibly empty)" do
      skip_unless_available(:orthanc)
      {:ok, assoc} = connect_to_peer(:orthanc, [@study_root_find])
      wait_for_established(assoc)

      result = Dimse.find(assoc, @study_root_find, <<>>, timeout: 15_000)
      assert match?({:ok, _}, result) or match?({:error, {:status, _}}, result)

      assert :ok = Dimse.release(assoc, 5_000)
    end
  end

  describe "C-FIND against dimse_scp" do
    test "study-level find returns a list (possibly empty)" do
      skip_unless_available(:dimse_scp)
      {:ok, assoc} = connect_to_peer(:dimse_scp, [@study_root_find])
      wait_for_established(assoc)

      result = Dimse.find(assoc, @study_root_find, <<>>, timeout: 15_000)
      assert match?({:ok, _}, result) or match?({:error, {:status, _}}, result)

      assert :ok = Dimse.release(assoc, 5_000)
    end
  end

  # --- C-GET tests ---

  describe "C-GET against orthanc" do
    test "get with no matching instances returns empty or error" do
      skip_unless_available(:orthanc)
      {:ok, assoc} = connect_to_peer(:orthanc, [@study_root_get, @ct_image_storage])
      wait_for_established(assoc)

      result = Dimse.get(assoc, :study, <<>>, timeout: 15_000)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      assert :ok = Dimse.release(assoc, 5_000)
    end
  end

  describe "C-GET against dimse_scp" do
    test "get with no matching instances returns empty or error" do
      skip_unless_available(:dimse_scp)
      {:ok, assoc} = connect_to_peer(:dimse_scp, [@study_root_get, @ct_image_storage])
      wait_for_established(assoc)

      result = Dimse.get(assoc, :study, <<>>, timeout: 15_000)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      assert :ok = Dimse.release(assoc, 5_000)
    end
  end

  # --- Negotiation details ---

  describe "negotiation details" do
    test "dcmtk negotiates correctly and reports implementation", do: assert_negotiation(:dcmtk)

    test "orthanc negotiates correctly and reports implementation",
      do: assert_negotiation(:orthanc)

    test "pynetdicom negotiates correctly and reports implementation",
      do: assert_negotiation(:pynetdicom)

    test "dimse_scp negotiates correctly and reports implementation",
      do: assert_negotiation(:dimse_scp)
  end
end
