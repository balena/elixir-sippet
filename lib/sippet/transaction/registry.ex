defmodule Sippet.Transaction.Registry do
  import Supervisor.Spec

  def registry_spec() do
    partitions = [partitions: System.schedulers_online()]
    registry_args = [:unique, __MODULE__, partitions]
    supervisor(Registry, registry_args)
  end

  def sup_spec(name) do
    sup_children = [worker(GenStateMachine, [], restart: :transient)]
    sup_opts = [strategy: :simple_one_for_one, name: name]
    worker(Supervisor, [sup_children, sup_opts])
  end

  def via_tuple(transaction) do
    {:via, Registry, {__MODULE__, transaction}}
  end

  def lookup(transaction),
    do: Registry.lookup(__MODULE__, transaction)
end
