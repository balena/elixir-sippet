defmodule Sippet.Transports.UDP.Sender do
  @moduledoc """
  A worker process responsible for transforming the SIP message in iodata and
  dispatching through the UDP socket.

  This process is managed by `poolboy` and it is started by
  `Sippet.Transports.UDP.Plug.start_link/0`.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Transports.UDP.Plug, as: Plug
  alias Sippet.Transports.UDP.Pool, as: Pool
  alias Sippet.Transactions, as: Transactions

  require Logger

  @doc """
  Starts the worker process.
  """
  def start_link(_), do: GenServer.start_link(__MODULE__, nil)

  @doc false
  def init(_) do
    socket = Plug.get_socket()
    Logger.debug(fn -> "#{inspect self()} udp sender ready" end)
    {:ok, socket}
  end

  @doc false
  def handle_cast({:send_message, message, host, port, key}, socket) do
    result =
      case :inet.getaddrs(String.to_charlist(host), :inet) do
        {:ok, [address|_]} ->
          iodata = Message.to_iodata(message)
          case :gen_udp.send(socket, {address, port}, iodata) do
            :ok -> :ok
            other -> other
          end
        other ->
          other
      end

    case result do
      :ok ->
        :ok
      {:error, reason} ->
        Logger.warn(fn -> "#{inspect self()} udp sender error for " <>
                          "#{host}:#{port}: #{inspect reason}" end)
        if key != nil do
          Transactions.receive_error(key, reason)
        end
    end

    Pool.check_in(self())
    {:noreply, socket}
  end

  @doc false
  def terminate(reason, _socket) do
    Logger.warn(fn -> "#{inspect self()} stopped udp sender, " <>
                      "reason #{inspect reason}" end)
  end
end
