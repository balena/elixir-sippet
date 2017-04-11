defmodule Sippet.Transport.Queue do
  @moduledoc """
  The transport queue receives datagrams or messages from network transport
  protocols, validates and routes them to the transaction module.

  The queue contains a worker pool to improve processing performance.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Transport.Pool, as: Pool

  @type from :: {
    protocol :: atom | binary,
    host :: String.t,
    dport :: integer
  }

  @spec incoming_datagram(String.t, from) :: :ok
  def incoming_datagram(datagram, from) do
    worker = Pool.check_out()
    GenServer.cast(worker, {:incoming_datagram, datagram, from})
  end

  @spec validate_message(message :: Message.t, from) :: :ok
  def validate_message(%Message{} = message, from) do
    worker = Pool.check_out()
    GenServer.cast(worker, {:validate_message, message, from})
  end
end
