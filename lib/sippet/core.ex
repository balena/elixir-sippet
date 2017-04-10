defmodule Sippet.Core do
  @moduledoc """
  A behaviour module for implementing the `Sippet.Core`.

  The `Sippet.Core` designates a particular type of SIP entity, i.e., specific
  to either a stateful or stateless proxy, a user agent or registrar.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Transaction, as: Transaction

  @doc """
  Receives a new incoming request from a remote host, or ACK.

  The `server_transaction` 
  """
  @callback receive_request(incoming_request :: Message.request,
                            server_transaction :: Transaction.Server.t | nil)
                            :: any

  @doc """
  Receives a response for a sent request.
  """
  @callback receive_response(incoming_response :: Message.response,
                             client_transaction :: Transaction.Client.t | nil)
                             :: any

  @doc """
  Sends receives an error from the transaction.
  """
  @callback receive_error(reason :: term,
                          client_or_server_transaction ::
                              Transaction.Client.t |
                              Transaction.Server.t)
                          :: any

  @doc """
  Dispatches the received request to the registered `Sippet.Core`
  implementation.
  """
  @spec receive_request(Message.request, Transaction.Server.t | nil) :: any
  def receive_request(incoming_request, server_transaction) do
    args = [incoming_request, server_transaction]
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
  @spec receive_response(Message.response, Transaction.Client.t | nil) :: any
  def receive_response(incoming_response, client_transaction) do
    args = [incoming_response, client_transaction]
    apply(get_module!(), :receive_response, args)
  end

  @doc """
  Dispatches the network transport error to the registered `Sippet.Core`
  implementation.
  """
  @spec receive_error(reason :: term,
                      Transaction.Client.t | Transaction.Server.t) :: any
  def receive_error(reason, client_or_server_transaction) do
    args = [reason, client_or_server_transaction]
    apply(get_module!(), :receive_error, args)
  end
end
