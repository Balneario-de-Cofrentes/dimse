defmodule Dimse.Test.TlsHelpers do
  @moduledoc """
  Generates self-signed CA, server, and client TLS certificates for tests.

  Uses OTP `:public_key` to create certificates dynamically — no files checked
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

    # Generate CA key pair and self-signed certificate
    ca_key = :public_key.generate_key({:rsa, 2048, 65_537})
    ca_cert = self_signed_cert(ca_key, "Dimse Test CA", is_ca: true)

    # Generate server key pair and CA-signed certificate (with SAN for localhost)
    server_key = :public_key.generate_key({:rsa, 2048, 65_537})
    server_cert = sign_cert(server_key, ca_key, ca_cert, "Dimse Test Server", san: true)

    # Generate client key pair and CA-signed certificate
    client_key = :public_key.generate_key({:rsa, 2048, 65_537})
    client_cert = sign_cert(client_key, ca_key, ca_cert, "Dimse Test Client")

    # Write PEM files
    cacertfile =
      write_pem(dir, "ca.pem", [
        {:Certificate, :public_key.der_encode(:Certificate, ca_cert), :not_encrypted}
      ])

    server_certfile =
      write_pem(dir, "server_cert.pem", [
        {:Certificate, :public_key.der_encode(:Certificate, server_cert), :not_encrypted}
      ])

    server_keyfile = write_pem(dir, "server_key.pem", [pem_entry(server_key)])

    client_certfile =
      write_pem(dir, "client_cert.pem", [
        {:Certificate, :public_key.der_encode(:Certificate, client_cert), :not_encrypted}
      ])

    client_keyfile = write_pem(dir, "client_key.pem", [pem_entry(client_key)])

    %{
      dir: dir,
      cacertfile: cacertfile,
      server_certfile: server_certfile,
      server_keyfile: server_keyfile,
      client_certfile: client_certfile,
      client_keyfile: client_keyfile
    }
  end

  # --- Certificate generation internals ---

  defp self_signed_cert(key, cn, opts) do
    serial = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned()
    is_ca = Keyword.get(opts, :is_ca, false)

    public_key = extract_public_key(key)
    issuer = {:rdnSequence, [[attr(:commonName, cn)]]}
    validity = validity(365 * 5)

    tbs =
      {:TBSCertificate, :v3, serial, signature_algorithm(), issuer, validity, issuer,
       public_key_info(public_key), :asn1_NOVALUE, :asn1_NOVALUE, extensions(is_ca)}

    sign_tbs(tbs, key)
  end

  defp sign_cert(subject_key, ca_key, ca_cert, cn, opts \\ []) do
    serial = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned()
    public_key = extract_public_key(subject_key)

    {:Certificate, {:TBSCertificate, _, _, _, issuer, _, _, _, _, _, _}, _, _} = ca_cert

    subject = {:rdnSequence, [[attr(:commonName, cn)]]}
    validity = validity(365)

    exts =
      if Keyword.get(opts, :san, false) do
        extensions(false) ++ [san_extension()]
      else
        extensions(false)
      end

    tbs =
      {:TBSCertificate, :v3, serial, signature_algorithm(), issuer, validity, subject,
       public_key_info(public_key), :asn1_NOVALUE, :asn1_NOVALUE, exts}

    sign_tbs(tbs, ca_key)
  end

  defp sign_tbs(tbs, key) do
    tbs_der = :public_key.der_encode(:TBSCertificate, tbs)
    signature = :public_key.sign(tbs_der, :sha256, key)

    {:Certificate, tbs, signature_algorithm(), signature}
  end

  defp signature_algorithm do
    {:SignatureAlgorithm, {1, 2, 840, 113_549, 1, 1, 11}, <<5, 0>>}
  end

  defp extract_public_key({:RSAPrivateKey, _, modulus, pub_exp, _, _, _, _, _, _, _}) do
    {:RSAPublicKey, modulus, pub_exp}
  end

  defp public_key_info(public_key) do
    der = :public_key.der_encode(:RSAPublicKey, public_key)
    algorithm = {:AlgorithmIdentifier, {1, 2, 840, 113_549, 1, 1, 1}, <<5, 0>>}
    {:SubjectPublicKeyInfo, algorithm, der}
  end

  defp validity(days) do
    now = :calendar.universal_time()
    not_before = format_time(now)
    not_after = format_time(add_days(now, days))
    {:Validity, {:utcTime, not_before}, {:utcTime, not_after}}
  end

  defp add_days({{y, m, d}, time}, days) do
    greg_days = :calendar.date_to_gregorian_days(y, m, d) + days
    {:calendar.gregorian_days_to_date(greg_days), time}
  end

  defp format_time({{y, m, d}, {h, min, s}}) do
    yy = rem(y, 100)

    :io_lib.format(~c"~2..0B~2..0B~2..0B~2..0B~2..0B~2..0BZ", [yy, m, d, h, min, s])
    |> IO.iodata_to_binary()
    |> to_charlist()
  end

  defp attr(:commonName, value) do
    # The value must be a DER-encoded binary (open type) for AttributeTypeAndValue
    encoded_value = :public_key.der_encode(:X520CommonName, {:utf8String, value})
    {:AttributeTypeAndValue, {2, 5, 4, 3}, encoded_value}
  end

  defp extensions(true) do
    [
      {:Extension, {2, 5, 29, 19}, true,
       :public_key.der_encode(:BasicConstraints, {:BasicConstraints, true, :asn1_NOVALUE})},
      {:Extension, {2, 5, 29, 15}, true,
       :public_key.der_encode(:KeyUsage, [:keyCertSign, :cRLSign])}
    ]
  end

  defp extensions(false) do
    [
      {:Extension, {2, 5, 29, 19}, false,
       :public_key.der_encode(:BasicConstraints, {:BasicConstraints, false, :asn1_NOVALUE})},
      {:Extension, {2, 5, 29, 15}, false,
       :public_key.der_encode(:KeyUsage, [:digitalSignature, :keyEncipherment])}
    ]
  end

  # SubjectAltName with 127.0.0.1 and localhost for test TLS connections
  defp san_extension do
    san_value = [
      {:iPAddress, <<127, 0, 0, 1>>},
      {:dNSName, ~c"localhost"}
    ]

    {:Extension, {2, 5, 29, 17}, false, :public_key.der_encode(:SubjectAltName, san_value)}
  end

  defp pem_entry({:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _} = key) do
    {:RSAPrivateKey, :public_key.der_encode(:RSAPrivateKey, key), :not_encrypted}
  end

  defp write_pem(dir, filename, entries) do
    path = Path.join(dir, filename)
    pem = :public_key.pem_encode(entries)
    File.write!(path, pem)
    path
  end
end
