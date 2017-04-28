defmodule Sippet.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Sippet.Transports.start_link()
    Sippet.Transactions.start_link()
  end
end
