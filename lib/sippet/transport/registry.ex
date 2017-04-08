defmodule Sippet.Transport.Registry do
  import Supervisor.Spec

  def spec() do
    partitions = System.schedulers_online()
    options = [:unique, __MODULE__, [partitions: partitions]]
    supervisor(Registry, options)
  end

  def via_tuple(module),
    do: {:via, Registry, {__MODULE__, module}}

  def via_tuple(module, host, port),
    do: {:via, Registry, {__MODULE__, {module, host, port}}}
end
