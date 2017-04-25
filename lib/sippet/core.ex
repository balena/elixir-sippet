defmodule Sippet.Core do
  @moduledoc """
  A behaviour module for implementing the `Sippet.Core`.

  The `Sippet.Core` designates a particular type of SIP entity, i.e., specific
  to either a stateful or stateless proxy, a user agent or registrar.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Transactions, as: Transactions

  @doc """
  Receives a new incoming request from a remote host, or ACK.

  The `server_key` indicates the name of the transaction created when
  the request was received. If it is an ACK, then the `server_key` is
  `nil`.

  The function `receive_request/2` is called from the server transaction
  process when the parameter `server_key` is not `nil`, and from the
  transport process (possibly a `poolboy` worker process), when the
  `server_key` is `nil`.
  """
  @callback receive_request(incoming_request :: Message.request,
                            server_key :: Transactions.Server.t | nil)
                            :: any

  @doc """
  Receives a response for a sent request.

  The `client_key` indicates the name of the transaction created when
  the request was sent using `Sippet.Transactions.send_request/1`.

  The function `receive_response/2` is called from the client transaction
  process when the parameter `client_key` is not `nil`, and from the
  transport process (possibly a `poolboy` worker process), when the
  `client_key` is `nil`.
  """
  @callback receive_response(incoming_response :: Message.response,
                             client_key :: Transactions.Client.t | nil)
                             :: any

  @doc """
  Receives an error from the server or client transaction.

  The function `receive_error/2` is called from the client or server
  transaction process created when sending or receiving requests.
  """
  @callback receive_error(reason :: term,
                          client_or_server_key ::
                              Transactions.Client.t |
                              Transactions.Server.t)
                          :: any

  @doc """
  Dispatches the received request to the registered `Sippet.Core`
  implementation.
  """
  @spec receive_request(Message.request, Transactions.Server.t | nil) :: any
  def receive_request(incoming_request, server_key) do
    args = [incoming_request, server_key]
    apply(get_module!(), :receive_request, args)
  end

  defp get_module!() do
    module = Application.get_env(:sippet, __MODULE__)
    if module == nil do
      raise RuntimeError, message: "Sippet.Core is not registered"
    else
      module
    end
  end

  @doc """
  Dispatches the received response to the registered `Sippet.Core`
  implementation.
  """
  @spec receive_response(Message.response, Transactions.Client.t | nil) :: any
  def receive_response(incoming_response, client_key) do
    args = [incoming_response, client_key]
    apply(get_module!(), :receive_response, args)
  end

  @doc """
  Dispatches the network transport error to the registered `Sippet.Core`
  implementation.
  """
  @spec receive_error(reason :: term,
                      Transactions.Client.t | Transactions.Server.t) :: any
  def receive_error(reason, client_or_server_key) do
    args = [reason, client_or_server_key]
    apply(get_module!(), :receive_error, args)
  end

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Sippet.Core
    end
  end
end
