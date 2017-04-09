defmodule Sippet.Transport.Plug do
  @moduledoc """
  A behaviour module for implementing `Sippet` transports.
  """

  @type message :: %Sippet.Message{}
  @type host :: binary
  @type dport :: integer
  @type transaction :: client_transaction | server_transaction | nil
  @type client_transaction :: Sippet.Transaction.Client.t
  @type server_transaction :: Sippet.Transaction.Server.t
  @type reason :: term

  @doc """
  Invoked to start listening for datagrams or connections.
  """
  @callback start_link() :: GenServer.on_start

  @doc """
  Invoked to send a message to the network. If any error occur while sending
  the message, and the transaction is not `nil`, the transaction should be
  informed so by calling `error/2`.
  """
  @callback send_message(message, host, dport, transaction) :: :ok | {:error, reason}

  @doc """
  Invoked to check if this connection is reliable (stream-based).
  """
  @callback reliable?() :: boolean

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Sippet.Transport.Plug
    end
  end
end
