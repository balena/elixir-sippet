defmodule Sippet.Transaction.Supervisor do
  import Supervisor.Spec

  @via_registry {:via, Registry, {Sippet.Transaction.Registry, __MODULE__}}

  def start_link() do
    partitions = [partitions: System.schedulers_online()]
    registry_args = [:unique, Sippet.Transaction.Registry, partitions]
    registry_spec = supervisor(Registry, registry_args)

    sup_children = [worker(GenStateMachine, [], restart: :transient)]
    sup_opts = [strategy: :simple_one_for_one, name: @via_registry]
    sup_spec = worker(Supervisor, [sup_children, sup_opts])

    options = [strategy: :one_for_one]

    Supervisor.start_link([registry_spec, sup_spec], options)
  end

  def start_child(module, %Sippet.Transaction.Client{} = name,
      %Sippet.Transaction.Client.State{} = initial_data) do
    Supervisor.start_child(@via_registry, [module, initial_data, [name: name]])
  end
  def start_child(module, %Sippet.Transaction.Server{} = name,
      %Sippet.Transaction.Server.State{} = initial_data) do
    Supervisor.start_child(@via_registry, [module, initial_data, [name: name]])
  end
end
