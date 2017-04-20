defmodule Sippet.Parser do
  @on_load {:init, 0}

  app = Mix.Project.config[:app]

  def init() do
    path = :filename.join(:code.priv_dir(unquote(app)), 'sippet_nif')
    :ok = :erlang.load_nif(path, 0)
  end

  def parse(message) when is_binary(message) do
    :erlang.nif_error(:not_loaded)
  end
end
