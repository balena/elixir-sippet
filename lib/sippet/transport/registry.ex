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

  def via_tuple(module),
    do: {:via, Registry, {__MODULE__, module}}

  def via_tuple(module, host, port),
    do: {:via, Registry, {__MODULE__, {module, host, port}}}
end
