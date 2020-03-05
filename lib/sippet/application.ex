defmodule Sippet.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, [name: Sippet.Registry, keys: :unique, partitions: System.schedulers_online()]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
