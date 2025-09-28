defmodule Sippet.Parser do
  @moduledoc """
  Communicates with the C++ NIF parser in order to parse the SIP header.

  The C++ NIF module was created to optimize the parsing.
  """

  @on_load {:init, 0}

  app = Mix.Project.config[:app]

  @doc """
  Initializes and loads the C++ NIF module.
  """
  def init() do
    path = :filename.join(:code.priv_dir(unquote(app)), ~c'sippet_nif')
    :ok = :erlang.load_nif(path, 0)
  end

  @doc """
  Parses the SIP message into an Erlang-like map.

  The `Sippet.Message` module translates the result into an Elixir-like struct.
  """
  def parse(message) when is_binary(message),
    do: :erlang.nif_error(:not_loaded)
end
