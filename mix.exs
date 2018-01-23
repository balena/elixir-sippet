defmodule Sippet.Mixfile do
  use Mix.Project

  @version "0.6.0"

  def project do
    [app: :sippet,
     version: @version,
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     compilers: [:make] ++ Mix.compilers, # Add the make compiler
     aliases: aliases(), # Configure aliases
     deps: deps(),
     package: package(),

     name: "Sippet",
     docs: [logo: "logo.png"],

     source_url: "https://github.com/balena/elixir-sippet",
     description: description(),

     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: [
       "coveralls": :test,
       "coveralls.detail": :test,
       "coveralls.post": :test,
       "coveralls.html": :test
     ]]
  end

  defp aliases do
    # Execute the usual mix clean and our Makefile clean task
    [clean: ["clean", "clean.make"]]
  end

  def application do
    [applications: [:logger, :gen_state_machine, :socket, :poolboy],
     mod: {Sippet.Application, []}]
  end

  defp deps do
    [{:gen_state_machine, "~> 2.0"},
     {:socket, "~> 0.3.5"},
     {:poolboy, "~> 1.5.1"},

     # Docs dependencies
     {:ex_doc, "~> 0.14", only: :dev, runtime: false},
     {:inch_ex, "~> 0.5", only: :docs},

     # Test dependencies
     {:mock, "~> 0.2.0", only: :test},
     {:excoveralls, "~> 0.6", only: :test},
     {:credo, "~> 0.7", only: [:dev, :test]},
     {:dialyxir, "~> 0.5", only: [:dev], runtime: false}]
  end

  defp description do
    """
    An Elixir library designed to be used as SIP protocol middleware.
    """
  end

  defp package do
    [maintainers: ["Guilherme Balena Versiani"],
     licenses: ["BSD"],
     links: %{"GitHub" => "https://github.com/balena/elixir-sippet"},
     files: ~w"lib c_src/*.{h,cc} c_src/Makefile mix.exs README.md LICENSE"]
  end
end

# Make tasks

defmodule Mix.Tasks.Compile.Make do
  # Compiles helper in c_src

  def run(_) do
    {result, error_code} = System.cmd("make", ["-C", "c_src"], stderr_to_stdout: true)

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
    {result, _error_code} = System.cmd("make", ["-C", "c_src", "clean"], stderr_to_stdout: true)
    Mix.shell.info result

    :ok
  end
end
