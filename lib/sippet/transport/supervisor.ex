defmodule Sippet.Transport.Supervisor do
  import Supervisor.Spec

  @doc false
  def start_link() do
    plug_conn_modules = Application.get_env(:sippet, __MODULE__)

    partitions = System.schedulers_online()
    options = [:unique, Sippet.Transport.Registry, partitions: partitions]
    registry_spec = supervisor(Registry, options)

    children = do_children_spec(plug_conn_modules, [registry_spec])

    options = [
      strategy: :one_for_one,
      name: __MODULE__
    ]

    Supervisor.start_link(children, options)
  end

  defp do_children_spec([], result), do: Enum.reverse(result)
  defp do_children_spec([{plug_module, conn_module}|rest], result) do
    new_result = [
      worker(plug_module, []),
      supervisor(Sippet.Transport.Conn.Supervisor, [conn_module])
      | result
    ]
    do_children_spec(rest, new_result)
  end
end
