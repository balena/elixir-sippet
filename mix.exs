defmodule Sippet.Mixfile do
  use Mix.Project

  @version "1.0.9"

  def project do
    [
      app: :sippet,
      version: @version,
      elixir: "~> 1.10",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      name: "Sippet",
      docs: [logo: "logo.png"],
      source_url: "https://github.com/balena/elixir-sippet",
      description: description(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:sippet_uri, "~> 0.1"},
      {:gen_state_machine, ">= 3.0.0"},

      # Docs dependencies
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:inch_ex, "~> 2.0", only: :docs},

      # Test dependencies
      {:mock, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.10", only: :test},
      {:credo, "~> 1.2", only: [:dev, :test]},
      {:dialyxir, ">= 1.0.0", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    An Elixir Session Initiation Protocol (SIP) stack.
    """
  end

  defp package do
    [
      maintainers: ["Guilherme Balena Versiani"],
      licenses: ["BSD"],
      links: %{"GitHub" => "https://github.com/balena/elixir-sippet"},
      files: ~w"lib c_src/*.{h,cc} c_src/Makefile mix.exs README.md LICENSE"
    ]
  end
end
