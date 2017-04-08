defmodule Sippet.Transport.UDP.Plug do
  use GenServer
  use Sippet.Transport.Plug

  import Supervisor.Spec

  require Logger

  @doc """
  Starts the UDP plug.
  """
  def start_link() do
    port =
      Application.get_env(:sippet, __MODULE__)
      |> Keyword.fetch!(:port)

    if port <= 0 do
      raise ArgumentError, "invalid port #{inspect port}"
    end

    children = [
      worker(Agent, [fn -> %{} end, [name: agent_name()]]),
      worker(GenServer, [__MODULE__, port])
    ]

    options = [
      strategy: :one_for_one,
      name: __MODULE__
    ]

    Supervisor.start_link(children, options)
  end

  defp agent_name(), do: Module.concat(__MODULE__, Agent)

  def get_socket(),
    do: Agent.get(agent_name(), fn %{socket: socket} -> socket end)

  def init(port) do
    sock_opts = [as: :binary, mode: :active]

    socket = Socket.UDP.open!(port, sock_opts)
    Agent.update(agent_name(), &Map.put(&1, :socket, socket))

    {:ok, {address, _port}} = :inet.sockname(socket)

    Logger.info("#{inspect self()} started plug " <>
                "#{:inet.ntoa(address)}:#{port}/udp")
    {:ok, {socket, address, port}}
  end

  def handle_info({:udp, _socket, ip, from_port, packet}, state) do
    Sippet.Transport.Queue.incoming_datagram(packet, {:udp, ip, from_port})
    {:noreply, state}
  end

  def handle_info(msg, state),
    do: super(msg, state)

  def terminate(reason, {socket, address, port}) do
    Logger.info("stopped plug #{:inet.ntoa(address)}:#{port}/udp, " <>
                "reason: #{inspect reason}")
    :ok = :gen_udp.close(socket)
  end

  def terminate(reason, state),
    do: super(reason, state)
end
