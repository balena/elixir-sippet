defmodule Sippet.Transport.Conn.Supervisor do
  import Supervisor.Spec

  @doc false
  def start_link(conn_module) do
    children = [
      worker(conn_module, [], restart: :transient)
    ]

    options = [
      strategy: :simple_one_for_one,
      name: via_tuple(conn_module)
    ]

    Supervisor.start_link(children, options)
  end

  defp via_tuple(module) do
    {:via, Registry, {Sippet.Transport.Registry, {__MODULE__, module}}}
  end

  @doc false
  def start_child(module, host, port) do
    name = via_tuple(module)
    Supervisor.start_child(name, [[host, port], []])
  end
end
