defmodule Sippet.PoolboyUtil do
  @moduledoc false

  @spec child_spec(module, module, Keyword.t) :: Supervisor.Spec.spec
  def child_spec(module, worker, defaults) do
    env_config = Application.get_env(:sippet, module)

    config =
      if env_config == nil do
        defaults
      else
        Keyword.merge(defaults,
          for {k, v} <- env_config, k in [:size, :max_overflow] do
            {k, v}
          end)
      end

    config =
      config
      |> Keyword.put(:name, {:local, module})
      |> Keyword.put(:worker_module, worker)

    :poolboy.child_spec(module, config, [])
  end

  @spec check_out(module) :: pid
  def check_out(module), do: :poolboy.checkout(module)

  @spec check_in(module, pid) :: :ok
  def check_in(module, worker), do: :poolboy.checkin(module, worker)
end
