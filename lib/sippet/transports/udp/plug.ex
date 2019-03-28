defmodule Sippet.Transports.UDP.Plug do
  @moduledoc """
  A `Sippet.Transports.Plug` implementing a UDP transport.

  The UDP transport consists basically in a listening process, this `Plug`
  implementation itself, and a pool of senders, defined in
  `Sippet.Transports.UDP.Sender`, managed by `poolboy`.

  The `start_link/0` function starts them, along a root supervisor that
  monitors them all in case of failures.

  This `Plug` process creates an UDP socket and keeps listening for datagrams
  in active mode. Its job is to forward the datagrams to the processing pool
  defined in `Sippet.Transports.Queue`. The sender processes pool keeps waiting
  for SIP messages (as defined by `Sippet.Message`), transforms them into
  iodata and dispatch them to the same UDP socket created by this `Plug`.

  Both pools will block if all worker processes are busy, which may happen only
  in high load surges, as both are pure processing pools.
  """

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
      :sippet
      |> Application.get_env(__MODULE__)
      |> Keyword.fetch!(:port)

    if port <= 0 do
      raise ArgumentError, "invalid port #{inspect port}"
    end

    address =
      :sippet
      |> Application.get_env(__MODULE__)
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

  @doc """
  Send a message to the UDP senders' pool.
  """
  def send_message(message, host, port, key) do
    conn = Pool.check_out()
    GenServer.cast(conn, {:send_message, message, host, port, key})
  end

  @doc """
  This connection is not reliable.
  """
  def reliable?(), do: false

  @doc """
  This blocking function gets called only during the senders' initialization.
  """
  def get_socket(),
    do: GenServer.call(__MODULE__, :get_socket, :infinity)

  @doc false
  def init([port, opts]) do
    open_socket(port, opts)
  end

  @doc false
  defp open_socket(port, opts) do
    sock_opts =
      [as: :binary, mode: :active] ++
      if Keyword.has_key?(opts, :address) do
        [local: [address: opts[:address]]]
      else
        []
      end

    case Socket.UDP.open(port, sock_opts) do
      {:ok, socket} ->
        {:ok, {address, _port}} = :inet.sockname(socket)
        Logger.info("#{inspect self()} started plug " <>
                    "#{:inet.ntoa(address)}:#{port}/udp")

        {:ok, {socket, address, port}}
      {:error, reason} ->
        Logger.error("#{inspect self()} port #{port}/udp " <>
                     "#{inspect reason}, retrying in 10s...")
        Process.sleep(10_000)
        open_socket(port, opts)
    end
  end

  @doc false
  def handle_info({:udp, _socket, ip, from_port, packet}, state) do
    Queue.incoming_datagram(packet, {:udp, ip, from_port})
    {:noreply, state}
  end

  @doc false
  def handle_call(:get_socket, _from, {socket, _address, _port} = state),
    do: {:reply, socket, state}

  @doc false
  def terminate(reason, {socket, address, port}) do
    Logger.info("#{inspect self()} stopped plug " <>
                "#{:inet.ntoa(address)}:#{port}/udp, " <>
                "reason: #{inspect reason}")
    :ok = :gen_udp.close(socket)
  end
end
