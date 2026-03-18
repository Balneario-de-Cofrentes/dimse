defmodule Dimse.TlsUnitTest do
  use ExUnit.Case, async: true

  alias Dimse.Tls

  describe "normalize_opts/1" do
    test "converts string paths to charlists for :certfile, :keyfile, :cacertfile" do
      opts = [
        certfile: "/path/to/cert.pem",
        keyfile: "/path/to/key.pem",
        cacertfile: "/path/to/ca.pem"
      ]

      result = Tls.normalize_opts(opts)

      assert result == [
               certfile: ~c"/path/to/cert.pem",
               keyfile: ~c"/path/to/key.pem",
               cacertfile: ~c"/path/to/ca.pem"
             ]
    end

    test "passes through charlist paths unchanged" do
      opts = [certfile: ~c"/path/to/cert.pem"]
      assert Tls.normalize_opts(opts) == opts
    end

    test "passes through non-path options unchanged" do
      opts = [verify: :verify_peer, fail_if_no_peer_cert: true, depth: 3]
      assert Tls.normalize_opts(opts) == opts
    end

    test "handles mixed path and non-path options" do
      opts = [
        certfile: "/path/to/cert.pem",
        verify: :verify_peer,
        keyfile: "/path/to/key.pem",
        depth: 2
      ]

      result = Tls.normalize_opts(opts)

      assert result == [
               certfile: ~c"/path/to/cert.pem",
               verify: :verify_peer,
               keyfile: ~c"/path/to/key.pem",
               depth: 2
             ]
    end

    test "handles empty list" do
      assert Tls.normalize_opts([]) == []
    end
  end
end
