defmodule Sippet do
  @moduledoc false

  use Supervisor

  @doc """
  Starts the Sippet supervision tree.
  """
  @spec start_link(list) :: Supervisor.on_start
  def start_link(args) when is_list(args),
    do: Supervisor.start_link(__MODULE__, args, name: __MODULE__)

  @impl true
  def init(_args) do
    children = [
      Sippet.Transports,
      Sippet.Transactions
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
