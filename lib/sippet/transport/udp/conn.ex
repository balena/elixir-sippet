defmodule Sippet.Transport.UDP.Conn do
  use Sippet.Transport.Conn

  require Logger

  def connect(address, port) do
    Logger.info("started conn #{:inet.ntoa(address)}:#{port}/udp")
    socket = Sippet.Transport.UDP.Plug.get_socket()
    {:ok, {socket, address, port}}
  end

  def send_message({socket, address, port}, message),
    do: Socket.Datagram.send(socket, message, {address, port})

  def reliable?(), do: false

  def terminate(reason, {_socket, address, port}) do
    Logger.info("stopped conn #{:inet.ntoa(address)}:#{port}/udp, " <>
                "reason: #{inspect reason}")
  end

  def terminate(reason, state),
    do: super(reason, state)
end
