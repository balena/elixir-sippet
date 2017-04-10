defmodule Sippet.Transport.Plug do
  @moduledoc """
  A behaviour module for implementing Sippet network transport protocols.

  A `Sippet.Transport.Plug` behavior module is started and supervised by the
  `Sippet.Transport` module at initialization.
  """

  @doc """
  Invoked to start listening for datagrams or connections.
  """
  @callback start_link() :: GenServer.on_start

  @doc """
  Invoked to send a message to the network. If any error occur while sending
  the message, and the transaction is not `nil`, the transaction should be
  informed so by calling `error/2`.
  """
  @callback send_message(message :: Sippet.Message.t,
                         remote_host :: binary,
                         remote_port :: integer,
                         transaction ::
                            Sippet.Transaction.Client.t |
                            Sippet.Transaction.Server.t |
                            nil)
                         :: :ok | {:error, reason :: term}

  @doc """
  Invoked to check if this connection is reliable (connection-oriented). If
  `false` then the `Sippet.Transaction` has to retransmit requests or handle
  request retransmissions.
  """
  @callback reliable?() :: boolean

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Sippet.Transport.Plug
    end
  end
end
