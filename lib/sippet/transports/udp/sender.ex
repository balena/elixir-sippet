defmodule Sippet.Transports.UDP.Sender do
  alias Sippet.Message, as: Message
  alias Sippet.Transports.UDP.Plug, as: Plug
  alias Sippet.Transports.UDP.Pool, as: Pool
  alias Sippet.Transactions, as: Transactions

  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, nil)

  def init(_) do
    socket = Plug.get_socket()
    Logger.info("#{inspect self()} udp worker ready")
    {:ok, socket}
  end

  @doc false
  def handle_cast({:send_message, message, host, port, transaction}, socket) do
    result =
      case Socket.Address.for(host, :inet) do
        {:ok, [address|_]} ->
          iodata = Message.to_iodata(message)
          case Socket.Datagram.send(socket, iodata, {address, port}) do
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
        Logger.warn("#{inspect self()} udp worker error for " <>
                    "#{host}:#{port}: #{inspect reason}")
        if transaction != nil do
          Transactions.receive_error(transaction, reason)
        end
    end

    Pool.check_in(self())
    {:noreply, socket}
  end

  def terminate(reason, _socket) do
    Logger.info("#{inspect self()} stopped udp worker, " <>
                "reason #{inspect reason}")
  end
end
