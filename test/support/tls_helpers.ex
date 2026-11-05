defmodule Dimse.Test.TlsHelpers do
  @moduledoc """
  Generates self-signed CA, server, and client TLS certificates for tests.

  Uses `:public_key.pkix_test_data/1` to create certificates dynamically — no files checked
  into the repo.
  """

  @doc """
  Generates a CA + server + client certificate chain and writes PEM files
  to a temporary directory.

  Returns a map with paths:

      %{
        cacertfile: "/tmp/.../ca.pem",
        server_certfile: "/tmp/.../server_cert.pem",
        server_keyfile: "/tmp/.../server_key.pem",
        client_certfile: "/tmp/.../client_cert.pem",
        client_keyfile: "/tmp/.../client_key.pem"
      }

  Call in `setup` and register an `on_exit` cleanup:

      setup do
        certs = Dimse.Test.TlsHelpers.generate_tls_certs()
        on_exit(fn -> File.rm_rf!(certs.dir) end)
        %{certs: certs}
      end
  """
  @spec generate_tls_certs() :: map()
  def generate_tls_certs do
    dir = Path.join(System.tmp_dir!(), "dimse_tls_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    ca = :public_key.pkix_test_root_cert(~c"Dimse Test CA", cert_opts())

    %{server_config: server, client_config: client} =
      :public_key.pkix_test_data(%{
        server_chain: %{
          root: ca,
          intermediates: [],
          peer: cert_opts(extensions: [san_extension()])
        },
        client_chain: %{root: ca, intermediates: [], peer: cert_opts()}
      })

    %{
      dir: dir,
      cacertfile: write_pem(dir, "ca.pem", cert_entry(ca.cert)),
      server_certfile: write_pem(dir, "server_cert.pem", cert_entry(server[:cert])),
      server_keyfile: write_pem(dir, "server_key.pem", key_entry(server[:key])),
      client_certfile: write_pem(dir, "client_cert.pem", cert_entry(client[:cert])),
      client_keyfile: write_pem(dir, "client_key.pem", key_entry(client[:key]))
    }
  end

  defp cert_opts(extra \\ []), do: [key: {:rsa, 2048, 65_537}, digest: :sha256] ++ extra

  # SubjectAltName with 127.0.0.1 and localhost for test TLS connections
  defp san_extension do
    {:Extension, {2, 5, 29, 17}, false,
     [{:iPAddress, <<127, 0, 0, 1>>}, {:dNSName, ~c"localhost"}]}
  end

  defp cert_entry(der), do: {:Certificate, der, :not_encrypted}

  defp key_entry({type, der}), do: {type, der, :not_encrypted}

  defp write_pem(dir, filename, entry) do
    path = Path.join(dir, filename)
    File.write!(path, :public_key.pem_encode([entry]))
    path
  end
end
