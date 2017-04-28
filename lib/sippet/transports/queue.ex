defmodule Sippet.Transports.Queue do
  @moduledoc """
  The transport queue receives datagrams or messages from network transport
  protocols, validates and routes them to the transaction module.

  The queue contains a worker pool to improve processing performance.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Transports.Pool, as: Pool

  @type from :: {
    protocol :: atom | binary,
    host :: String.t,
    dport :: integer
  }

  @doc """
  Dispatches an incoming datagram to be parsed by one of the pool workers.

  The pool worker is responsible for moving the message up on the stack.

  The `datagram` is a datagram packet just received from the transport that
  needs to get parsed and validated before handled by transactions or the core.

  The `from` parameter is a tuple containing the protocol, the host name and
  the port of the socket that received the datagram.
  """
  @spec incoming_datagram(String.t, from) :: :ok
  def incoming_datagram(datagram, from) do
    worker = Pool.check_out()
    GenServer.cast(worker, {:incoming_datagram, datagram, from})
  end

  @doc """
  Dispatches an incoming message to be validated by one of the pool workers.

  The pool worker is responsible for moving the message up on the stack.

  The `message` is a `Sippet.Message` struct normally built from a stream
  socket, that still needs to be validated.

  The `from` parameter is a tuple containing the protocol, the host name and
  the port of the socket that received the message.
  """
  @spec validate_message(message :: Message.t, from) :: :ok
  def validate_message(%Message{} = message, from) do
    worker = Pool.check_out()
    GenServer.cast(worker, {:validate_message, message, from})
  end
end
