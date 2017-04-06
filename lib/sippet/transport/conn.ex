defmodule Sippet.Transport.Conn do
  @moduledoc """
  A behaviour module for implementing a transport connection.

  This module defines the behavior all transport connections have to implement.
  """

  @type host :: binary
  @type address :: :inet.ip_address
  @type dport :: integer
  @type socket :: term
  @type message :: iodata
  @type reason :: term
  @type transaction :: port | nil

  @type on_via_tuple ::
    {:via, module, {module, {module, host, port}}}

  @doc """
  Connects to the given `address` and `port`.
  """
  @callback connect(address, dport) :: {:ok, socket} | {:error, reason}

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

  defmacro __using__(_opts) do
    quote location: :keep do
      use GenServer

      @doc false
      def start_link(host, port) do
        name = Sippet.Transport.Conn.via_tuple(__MODULE__, host, port)
        GenServer.start_link(__MODULE__, {host, port}, name: name)
      end

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
        case :inet.getaddr(String.to_charlist(host), :inet) do
          {:error, reason} ->
            {:stop, reason, {nil}}
          {:ok, address} ->
            case connect(address, port) do
              {:ok, socket} -> {:noreply, {socket}}
              {:error, reason} -> {:stop, reason, {nil}}
            end
        end
      end

      @doc false
      def handle_info({:send, message, transaction}, {socket}) do
        case send(socket, Message.to_iodata(message)) do
          :ok ->
            {:ok, {socket}}
          {:error, reason} ->
            if transaction != nil do
              Sippet.Transaction.on_error(transaction, reason)
            end

            {:stop, reason, {socket}}
        end
      end

      @doc false
      def handle_info(msg, state), do: super(msg, state)

      defoverridable [init: 1, handle_info: 2]
    end
  end

  @spec via_tuple(module, host, dport) :: on_via_tuple
  def via_tuple(module, host, port) do
    {:via, Registry, {Sippet.Transport.Registry, {module, host, port}}}
  end

  @spec send_message(module, host, dport, message, transaction) :: :ok
  def send_message(module, host, port, message, transaction) do
    name = via_tuple(module, host, port)
    GenServer.cast(name, {:send, message, transaction})
  end
end
