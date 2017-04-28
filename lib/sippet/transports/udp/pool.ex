defmodule Sippet.Transports.UDP.Pool do
  @moduledoc """
  This module defines the UDP senders' pool.

  The objective is to block the caller case all worker processes are busy in
  order to keep the system responsive.
  """

  @doc """
  Returns a `poolboy` child specification for a parent supervisor.
  """
  @spec spec() :: Supervisor.Spec.spec
  def spec() do
    alias Sippet.Transports.UDP.Sender, as: Sender

    defaults = [
      size: System.schedulers_online(),

      # overflow is generally useless, as workers
      # will do busy processing
      max_overflow: 0
    ]

    Sippet.PoolboyUtil.child_spec(__MODULE__, Sender, defaults)
  end

  @doc """
  Checks out a worker from the pool to send the message.

  This operation is performed by `Sippet.Transports.UDP.Plug.send_message/4`.

  While the calling process is responsible to check out a worker process, the
  worker process will be responsible to check in itself once it becomes ready
  for another message.
  """
  @spec check_out() :: pid
  def check_out(), do: Sippet.PoolboyUtil.check_out(__MODULE__)

  @doc """
  Checks in a worker back to the pool, becoming ready to send another message.

  This operation is performed by `Sippet.Transports.UDP.Sender.handle_cast/2`.

  While the calling process is responsible to check out a worker process, the
  worker process will be responsible to check in itself once it becomes ready
  for another message.
  """
  @spec check_in(pid) :: :ok
  def check_in(worker), do: Sippet.PoolboyUtil.check_in(__MODULE__, worker)
end
