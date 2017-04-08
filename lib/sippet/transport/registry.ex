defmodule Sippet.Transport.Registry do
  import Supervisor.Spec

  def registry_spec() do
    partitions = System.schedulers_online()
    options = [:unique, __MODULE__, [partitions: partitions]]
    supervisor(Registry, options)
  end

  def plug_spec(module), do: worker(module, [])

  def conn_spec(module), do: worker(module, [], restart: :transient)

  def conn_sup_spec(protocol),
    do: supervisor(Sippet.Transport.Conn, [protocol])

  def pool_spec() do
    alias Sippet.Transport.Worker, as: Worker

    defaults = [
      name: {:local, Worker},
      worker_module: Worker,
      size: System.schedulers_online(),

      # overflow is generally useless, as workers
      # will do busy processing
      max_overflow: 0
    ]

    env_config = Application.get_env(:sippet, Sippet.Transport.Pool)

    config =
      if env_config == nil do
        defaults
      else
        accepted = [:size, :max_overflow]
        Keyword.merge(defaults,
          for {k, v} <- env_config, Enum.member?(accepted, k) do
            {k, v}
          end)
      end

    :poolboy.child_spec(Sippet.Transport.Pool, config, [])
  end

  def via_tuple(module),
    do: {:via, Registry, {__MODULE__, module}}

  def via_tuple(module, host, port),
    do: {:via, Registry, {__MODULE__, {module, host, port}}}
end
