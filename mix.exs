defmodule Sippet.Mixfile do
  use Mix.Project

  @version "0.6.4"

  def project do
    [
      app: :sippet,
      version: @version,
      elixir: "~> 1.8",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
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
      ],
      make_clean: ["clean"],
      make_cwd: "c_src"
    ]
  end

  def application do
    [
      applications: [:logger, :gen_state_machine, :socket, :poolboy],
      mod: {Sippet.Application, []}
    ]
  end

  defp deps do
    [
      {:gen_state_machine, "~> 2.0"},

      # Build the NIF
      {:elixir_make, "~> 0.4", runtime: false},

      {:socket, "~> 0.3.13"},
      {:poolboy, "~> 1.5"},

      # Docs dependencies
      {:ex_doc, "~> 0.19.3", only: :dev, runtime: false},
      {:inch_ex, "~> 2.0", only: :docs},

      # Test dependencies
      {:mock, "~> 0.3.3", only: :test},
      {:excoveralls, "~> 0.10.6", only: :test},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
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
