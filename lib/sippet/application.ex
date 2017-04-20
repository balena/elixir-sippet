defmodule Sippet.Application do
  use Application

  def start(_type, _args) do
    Sippet.Transports.start_link()
    Sippet.Transactions.start_link()
  end
end
