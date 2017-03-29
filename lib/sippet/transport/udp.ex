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

  alias Sippet.Message, as: Message
  alias Sippet.Transport.Udp.State, as: State

  require Logger

  @doc """
  Starts the UDP transport on informed host and port.
  """
  def start_link(host, port, family)
      when is_binary(host) and is_integer(port) and is_atom(family) do
    if port <= 0 do
      raise ArgumentError, "invalid port #{port}"
    end
    GenServer.start_link(__MODULE__,
        %State{host: host, port: port, family: family})
  end

  @doc """
  Sends a SIP message to the given destination.
  """
  def send(pid, %Message{} = message, {host, port}) do
    GenServer.cast(pid, {:send, message, {host, port}})
  end

  def init(%State{host: host, port: port, family: family} = state) do
    ip = case :inet.getaddr(host, family) do
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

  defp dispatch_message(_message, _from_ip, _from_port, _family) do
    # TODO(guibv): pass the message up the stack
  end

  def handle_cast({:send, message, {host, port}}, %State{socket: socket} = state) do
    :gen_udp.send(socket, host, port, Message.to_string(message))
    {:noreply, state}
  end
end
