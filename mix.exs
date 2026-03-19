defmodule Dimse.MixProject do
  use Mix.Project

  @version "0.8.2"
  @source_url "https://github.com/Balneario-de-Cofrentes/dimse"

  def project do
    [
      app: :dimse,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "Dimse",
      description:
        "Pure Elixir DICOM DIMSE networking library — Upper Layer Protocol, SCP/SCU services",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      preferred_cli_env: [
        test: :test,
        "test.all": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl, :public_key]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:dicom, "~> 0.4"},
      {:ranch, "~> 2.1"},
      {:telemetry, "~> 1.0"},

      # Dev/test only
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:benchee, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/dimse",
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      },
      files:
        ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md SECURITY.md AGENTS.md CONTRIBUTING.md CODE_OF_CONDUCT.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "SECURITY.md",
        "AGENTS.md",
        "CONTRIBUTING.md",
        "CODE_OF_CONDUCT.md",
        "LICENSE"
      ],
      source_ref: System.get_env("SOURCE_REF") || "v#{@version}"
    ]
  end
end
