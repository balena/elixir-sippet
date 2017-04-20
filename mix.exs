defmodule Sippet.Mixfile do
  use Mix.Project

  def project do
    [app: :sippet,
     version: "0.2.4",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     compilers: [:make] ++ Mix.compilers, # Add the make compiler
     aliases: aliases(), # Configure aliases
     deps: deps(),
     description: description(),
     package: package(),
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: [
       "coveralls": :test,
       "coveralls.detail": :test,
       "coveralls.post": :test,
       "coveralls.html": :test
     ],
     dialyzer: [ignore_warnings: "dialyzer.ignore-warnings"]]
  end

  defp aliases do
    # Execute the usual mix clean and our Makefile clean task
    [clean: ["clean", "clean.make"]]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :gen_state_machine, :socket, :poolboy],
     mod: {Sippet.Application, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:dialyxir, "~> 0.5", only: [:dev], runtime: false},
     {:credo, "~> 0.7", only: [:dev, :test]},
     {:gen_state_machine, "~> 2.0"},
     {:socket, "~> 0.3.5"},
     {:poolboy, "~> 1.5.1"},
     {:ex_doc, "~> 0.15.1", only: :dev, runtime: false},
     {:inch_ex, "~> 0.5", only: :docs},
     {:mock, "~> 0.2.0", only: :test},
     {:excoveralls, "~> 0.6", only: :test}]
  end

  defp description do
    """
    An Elixir library designed to be used as SIP protocol middleware.
    """
  end

  defp package do
    [# These are the default files included in the package
     name: :sippet,
     files: ["lib", "c_src/*.{h,cc}", "c_src/Makefile", "support/getrebar",
             "mix.exs", "README.md", "LICENSE", "Makefile", "rebar.config"],
     maintainers: ["Guilherme Balena Versiani"],
     licenses: ["BSD"],
     links: %{"GitHub" => "https://github.com/balena/elixir-sippet"}]
  end
end

# Make tasks

defmodule Mix.Tasks.Compile.Make do
  # Compiles helper in c_src

  def run(_) do
    {result, error_code} = System.cmd("make", [], stderr_to_stdout: true)

    # XXX(balena): Because the compiler changes the priv directory, we need to
    # notify Mix to rebuild the project structure under _build, copying the new
    # priv files.
    # https://github.com/riverrun/comeonin/pull/41/commits/5670e424f7d4feba0839211090f5dcf79b340577
    if error_code == 0 do
      Mix.Project.build_structure
    end

    Mix.shell.info result

    :ok
  end
end

defmodule Mix.Tasks.Clean.Make do
  # Cleans helper in c_src

  def run(_) do
    {result, _error_code} = System.cmd("make", ['clean'], stderr_to_stdout: true)
    Mix.shell.info result

    :ok
  end
end
