defmodule Sippet.Transport.UDP.Plug do
  use GenServer
  
  @behaviour Sippet.Transport.Plug

  alias Sippet.Message, as: Message

  require Logger

  @doc """
  Starts the UDP plug.
  """
  def start_link(listen_port, sock_opts, options) do
    if listen_port <= 0 do
      raise ArgumentError, "invalid port #{listen_port}"
    end

    {:ok, _} = Registry.start_link(:unique, __MODULE__)

    GenServer.start_link(__MODULE__,
        %{port: listen_port, sock_opts: sock_opts}, options)
  end
  
  def reliable?(), do: false

  def get_socket() do
    [{_parent_pid, socket}] = Registry.lookup(__MODULE__, :socket)
    socket
  end

  def init(%{port: port, sock_opts: sock_opts} = state) do
    sock_opts =
      sock_opts
      |> Keyword.put(:as, :binary)
      |> Keyword.put(:mode, :active)

    socket = Socket.UDP.open!(port, sock_opts)
    {:ok, {address, _port}} = :inet.sockname(socket)
    address = :inet.ntoa(address)

    Logger.info("started plug #{address}:#{port}/udp")

    state =
      state
      |> Map.put(:socket, socket)
      |> Map.put(:address, address)
      |> Map.delete(:sock_opts)

    Registry.register(__MODULE__, :socket, socket)

    {:ok, state}
  end

  def handle_info({:udp, _socket, ip, from_port, packet}, _state) do
    host = to_string(:inet.ntoa(ip))
    {_conn_module, conn} =
      Sippet.Transport.Registry.get_connection(:udp, host, from_port)

    Sippet.Transport.UDP.Conn.receive_packet(conn, packet)
  end

  def terminate(reason,
      %{socket: socket, address: address, port: port}) do
    Logger.info("stopped plug #{address}:#{port}/udp, " <>
                "reason: #{inspect reason}")
    :ok = :gen_udp.close(socket)
  end
end

defmodule Sippet.Transport.UDP.Conn do
  use GenServer
  use Sippet.Transport.Conn

  alias Sippet.Message, as: Message

  require Logger

  @doc """
  Starts the UDP Conn.
  """
  def start_link({host, port}, options) do
    GenServer.start_link(__MODULE__, %{host: host, port: port}, options)
  end

  def send_message(conn, %Message{} = message, transaction),
    do: GenServer.cast(conn, {:send, message, transaction})

  def receive_packet(conn, packet),
    do: GenServer.cast(conn, {:receive, packet})

  def init(%{host: host, port: port} = state) do
    socket = Sippet.Transport.UDP.get_socket()

    {:ok, %Socket.Host{list: [ip|_]}} = Socket.Host.by_name(host)
    address = to_string(:inet.ntoa(ip))

    Logger.info("started conn #{address}:#{port}/udp")

    state =
      state
      |> Map.put(:socket, socket)
      |> Map.put(:address, address)

    {:ok, state}
  end

  def handle_cast({:send, message, transaction},
      %{socket: socket, host: host, port: port} = state) do
    iodata = Message.to_iodata(message)
    case Socket.Datagram.send(socket, iodata, {host, port}) do
      {:error, reason} ->
        if transaction != nil do
          error(reason, transaction)
        end
      _other ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:receive, packet}, %{host: host, port: port} = state) do
    case do_parse_message(packet) do
      {:ok, message} ->
        do_receive_message(message, host, port)
      {:error, reason} ->
        Logger.error("couldn't parse incoming packet from " <>
                     "#{host}:#{port}, reason: #{inspect reason}")
    end

    {:noreply, state}
  end

  defp do_parse_message(packet) do
    message = String.replace(packet, "\r\n", "\n")
    case String.split(message, "\n\n", parts: 2) do
      [header, body] ->
        do_parse_message(header <> "\n\n", body)
      [header] ->
        do_parse_message(header, "")
    end
  end

  defp do_parse_message(header, body) do
    case Message.parse(header) do
      {:ok, message} -> {:ok, %{message | body: body}}
      other -> other
    end
  end

  defp do_receive_message(message, ip, from_port) do
    if Message.response?(message) do
      message |> Message.update_header_back(:via, nil,
        fn({version, protocol, {host, port}, params}) ->
          params =
            if host != ip do
              %{params | "received" => ip}
            else
              params
            end
      
          params =
            if port != from_port do
              %{params | "rport" => to_string(from_port)}
            else
              params
            end
      
          {version, protocol, {host, port}, params}
        end)
    else
      message
    end
    |> receive_message()
  end

  def terminate(reason, %{address: address, port: port}) do
    Logger.info("stopped conn #{address}:#{port}/udp, " <>
                "reason: #{inspect reason}")
  end
end
