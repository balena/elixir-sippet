defmodule Sippet.Transport.Udp.State do
  defstruct [
    host: nil,
    port: nil,
    family: nil,
    socket: nil
  ]
end

defmodule Sippet.Transport.Udp do
  use GenServer

  @behaviour Sippet.Transport

  alias Sippet.Message, as: Message
  alias Sippet.Router, as: Router
  alias Sippet.Transport.Udp.State, as: State

  require Logger

  defstruct [
    pid: nil
  ]

  @type t :: %__MODULE__{
    pid: pid()
  }

  @doc """
  Starts the UDP transport on informed host and port.
  """
  def start_link(host, port, family)
      when is_binary(host) and is_integer(port) and is_atom(family) do
    if port <= 0 do
      raise ArgumentError, "invalid port #{port}"
    end

    {:ok, pid} = GenServer.start_link(__MODULE__,
        %State{host: host, port: port, family: family})

    %__MODULE__{pid: pid}
  end

  def start_child(_host, _port, _opts) do
    # TODO: create a client-only process reusing the same socket
  end

  def reliable?(), do: false

  def send(transport, message) do
    GenServer.cast(transport, {:send, message})
  end

  def init(%State{host: host, port: port, family: family} = state) do
    ip = case :inet.getaddr(String.to_charlist(host), family) do
      {:ok, ip} ->
        ip
      {:error, reason} ->
        raise ArgumentError, "cannot resolve #{inspect host}, " <>
                             "reason: #{inspect reason}"
    end

    {:ok, socket} = :gen_udp.open(port, [:binary, family,
        {:ip, ip}, {:active, true}])

    Logger.info("started #{host}:#{port}/UDP")

    {:ok, %{state | socket: socket}}
  end

  def terminate(reason, %State{socket: socket, host: host, port: port})
      when socket != nil do
    Logger.info("stopped #{host}:#{port}/UDP, reason: #{inspect reason}")
    :ok = :gen_udp.close(socket)
  end

  def handle_info({:udp, _socket, ip, from_port, packet},
      %State{family: family} = state) do
    case parse_message(packet) do
      {:ok, message} ->
        dispatch_message(message, ip, from_port, family)
      {:error, reason} ->
        Logger.error("couldn't parse incoming packet from " <>
                     "#{ip}:#{from_port}, reason: #{inspect reason}")
    end
    {:noreply, state}
  end

  defp parse_message(packet) do
    simplified = String.replace(packet, "\r\n", "\n")
    case String.split(simplified, "\n\n", parts: 2) do
      [header, body] ->
        parse_message(header <> "\n\n", body)
      [header] ->
        parse_message(header, "")
    end
  end

  defp parse_message(header, body) do
    case Message.parse(header) do
      {:ok, message} -> {:ok, %{message | body: body}}
      other -> other
    end
  end

  defp dispatch_message(message, from_ip, from_port, _family) do
    received = to_string(:inet.ntoa(from_ip))
    message = Message.update_header_back(message, :via, nil,
      fn({version, protocol, {host, port}, params}) ->
        params =
          if host != received do
            %{params | "received" => received}
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

    # TODO(guibv): The child process should be used here
    Router.receive(self(), message)
  end

  def handle_cast({:send, message, {host, port}}, %State{socket: socket} = state) do
    :gen_udp.send(socket, host, port, Message.to_string(message))
    {:noreply, state}
  end
end
