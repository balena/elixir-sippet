defmodule Sippet.Transactions.Registry do
  @moduledoc false

  import Supervisor.Spec

  def registry_spec() do
    partitions = [partitions: System.schedulers_online()]
    registry_args = [:unique, __MODULE__, partitions]
    supervisor(Registry, registry_args)
  end

  def via_tuple(transaction) do
    {:via, Registry, {__MODULE__, transaction}}
  end

  def lookup(transaction),
    do: Registry.lookup(__MODULE__, transaction)
end
