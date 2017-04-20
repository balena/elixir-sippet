defmodule Sippet.Transports.UDP.Plug do
  use GenServer
  use Sippet.Transports.Plug

  alias Sippet.Transports.UDP.Pool, as: Pool
  alias Sippet.Transports.Queue, as: Queue

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

    address =
      Application.get_env(:sippet, __MODULE__)
      |> Keyword.get(:address)

    opts =
      case address do
        nil -> []
        ip -> [address: ip]
      end

    children = [
      worker(GenServer, [__MODULE__, [port, opts], [name: __MODULE__]]),
      Pool.spec()
    ]

    Supervisor.start_link(children, [strategy: :one_for_all])
  end

  def send_message(message, host, port, transaction) do
    conn = Pool.check_out()
    GenServer.cast(conn, {:send_message, message, host, port, transaction})
  end

  def reliable?(), do: false

  def get_socket(),
    do: GenServer.call(__MODULE__, :get_socket, :infinity)

  def init([port, opts]) do
    sock_opts =
      [as: :binary, mode: :active] ++
      if Keyword.has_key?(opts, :address) do
        [local: [address: opts[:address]]]
      else
        []
      end

    socket = Socket.UDP.open!(port, sock_opts)

    {:ok, {address, _port}} = :inet.sockname(socket)
    Logger.info("#{inspect self()} started plug " <>
                "#{:inet.ntoa(address)}:#{port}/udp")

    {:ok, {socket, address, port}}
  end

  def handle_info({:udp, _socket, ip, from_port, packet}, state) do
    Queue.incoming_datagram(packet, {:udp, ip, from_port})
    {:noreply, state}
  end

  def handle_info(request, state),
    do: super(request, state)

  def handle_call(:get_socket, _from, {socket, _address, _port} = state),
    do: {:reply, socket, state}

  def handle_call(request, from, state),
    do: super(request, from, state)

  def terminate(reason, {socket, address, port}) do
    Logger.info("#{inspect self()} stopped plug " <>
                "#{:inet.ntoa(address)}:#{port}/udp, " <>
                "reason: #{inspect reason}")
    :ok = :gen_udp.close(socket)
  end

  def terminate(reason, state),
    do: super(reason, state)
end
