defmodule Sippet.PoolboyUtil do
  @spec child_spec(module, module, Keyword.t) :: Supervisor.Spec.spec
  def child_spec(module, worker, defaults) do
    env_config = Application.get_env(:sippet, module)

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

    config =
      config
      |> Keyword.put(:name, {:local, worker})
      |> Keyword.put(:worker_module, worker)

    :poolboy.child_spec(module, config, [])
  end

  @spec check_out(module) :: pid
  def check_out(module), do: :poolboy.checkout(module)

  @spec check_in(module, pid) :: :ok
  def check_in(module, worker), do: :poolboy.checkin(module, worker)
end
