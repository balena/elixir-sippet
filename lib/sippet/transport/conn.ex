defmodule Sippet.Transport.Conn do
  @moduledoc """
  A behaviour module for implementing a transport connection.

  This module defines the behavior all transport connections have to implement.
  """

  import Supervisor.Spec
  import Sippet.Transport.Registry

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
  @callback send_message(socket, message) :: :ok | {:error, reason}

  @doc """
  Invoked to check if this connection is reliable (stream-based).
  """
  @callback reliable?() :: boolean

  @doc """
  Starts a supervisor responsible for connections.

  This function is called from the `start_link/0` function and it is not
  intended to be used alone.
  """
  @spec start_link(protocol :: atom | binary) :: Supervisor.on_start
  def start_link(protocol) do
    module = get_connection_module(protocol)

    children = [
      worker(module, [], restart: :transient)
    ]

    options = [
      strategy: :simple_one_for_one,
      name: via_tuple(module)
    ]

    Supervisor.start_link(children, options)
  end

  defp get_connection_module(protocol) do
    Application.get_env(:sippet, Sippet.Transport)
    |> Keyword.fetch!(:conns)
    |> Keyword.fetch!(protocol)
  end

  @doc """
  Ensures that a given connection has started.
  """
  def start_connection(protocol, host, port, message, transaction) do
    module = get_connection_module(protocol)
    name = via_tuple(module)
    child_name = via_tuple(module, host, port)
    Supervisor.start_child(name,
        [host, port, message, transaction, [name: child_name]])
  end

  @spec send_message(GenServer.server, %Message{}, transaction) :: :ok
  def send_message(server, message, transaction),
    do: GenServer.cast(server, {:send, message, transaction})

  @spec reliable?(protocol :: atom | binary) :: boolean
  def reliable?(protocol),
    do: get_connection_module(protocol) |> apply(:reliable?, [])

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Sippet.Transport.Conn

      use GenServer

      @doc false
      def start_link(host, port, message, transaction, options) do
        initial_state = {host, port, message, transaction}
        GenServer.start_link(__MODULE__, initial_state, options)
      end

      @doc false
      def init(state) do
        self() |> Process.send_after(:connect, 0)
        {:ok, state}
      end

      @doc false
      def handle_info(:connect, {host, port, message, transaction}) do
        case Socket.Address.for(host, :inet) do
          {:error, reason} ->
            {:stop, reason, nil}
          {:ok, [address|_]} ->
            case connect(address, port) do
              {:error, reason} ->
                {:stop, reason, nil}
              {:ok, socket} ->
                send_message(socket, message, transaction)
            end
        end
      end
      
      def handle_info(msg, state), do: super(msg, state)

      def handle_cast({:send, message, transaction}, socket),
        do: send_message(socket, message, transaction)

      def handle_cast(msg, state), do: super(msg, state)

      defp send_message(socket, message, transaction) do
        case send_message(socket, Message.to_iodata(message)) do
          :ok ->
            {:noreply, socket}
          {:error, reason} ->
            if transaction != nil do
              Sippet.Transaction.receive_error(transaction, reason)
            end

            {:stop, reason, socket}
        end
      end

      def connect(address, port), do: {:error, :not_implemented}

      defoverridable [init: 1, handle_info: 2, connect: 2]
    end
  end
end
