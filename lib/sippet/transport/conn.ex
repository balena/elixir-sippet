defmodule Sippet.Transport.Conn do
  @moduledoc """
  A behaviour module for implementing a transport connection.

  This module defines the behavior all transport connections have to implement.
  """

  alias Sippet.Message, as: Message

  @type host :: binary
  @type address :: :inet.ip_address
  @type dport :: integer
  @type socket :: term
  @type message :: iodata
  @type reason :: term
  @type transaction :: client_transaction | server_transaction | nil
  @type client_transaction :: Sippet.Transaction.Client.t
  @type server_transaction :: Sippet.Transaction.Server.t

  @type on_via_tuple ::
    {:via, module, {module, {module, host, port}}}

  @doc """
  Connects to the given `address` and `port`.
  """
  @callback connect(address, dport) :: term | no_return

  @doc """
  Invoked to send a message to the given `socket`. If any error occur while
  sending the message, and the transaction is not `nil`, the transaction should
  be informed so by calling `error/2`.
  """
  @callback send(socket, message) :: :ok | {:error, reason}

  @doc """
  Invoked to check if this connection is reliable (stream-based).
  """
  @callback reliable?() :: boolean


  @spec send_message(GenServer.server, %Message{}, transaction) :: :ok
  def send_message(server, message, transaction),
    do: GenServer.cast(server, {:send, message, transaction})

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Sippet.Transport.Conn

      use GenServer

      @doc false
      def start_link(host, port, options),
        do: GenServer.start_link(__MODULE__, {host, port}, options)

      @doc false
      def init(state) do
        do_schedule_connect()
        {:ok, state}
      end

      defp do_schedule_connect() do
        Process.send_after(self(), :connect, 0)
      end

      @doc false
      def handle_info(:connect, {host, port}) do
        case Socket.Address.for(host, :inet) do
          {:error, reason} ->
            {:stop, reason, {nil}}
          {:ok, [address|_]} ->
            case connect(address, port) do
              {:ok, socket} -> {:noreply, socket}
              {:error, reason} -> {:stop, reason, nil}
            end
        end
      end

      def handle_info({:send, message, transaction}, socket) do
        case send(socket, Message.to_iodata(message)) do
          :ok ->
            {:ok, socket}
          {:error, reason} ->
            if transaction != nil do
              Sippet.Transaction.receive_error(transaction, reason)
            end

            {:stop, reason, socket}
        end
      end

      def handle_info(msg, state), do: super(msg, state)

      def connect(address, port), do: {:error, :not_implemented}

      defoverridable [init: 1, handle_info: 2, connect: 2]
    end
  end
end
