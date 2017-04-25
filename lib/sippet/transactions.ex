defmodule Sippet.Transactions do
  @moduledoc """
  The `Sippet.Transactions` is responsible to dispatch messages from
  `Sippet.Transports` and `Sippet.Core` modules to transactions, creating when
  necessary.
  """

  import Supervisor.Spec
  import Sippet.Transactions.Registry

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transactions, as: Transactions
  alias Sippet.Core, as: Core

  require Logger

  @typedoc "A SIP message request"
  @type request :: Message.request

  @typedoc "A SIP message response"
  @type response :: Message.response

  @typedoc "An network error that occurred while sending a message"
  @type reason :: term

  @typedoc "A client transaction identifier"
  @type client_key :: Transactions.Client.Key.t

  @typedoc "A server transaction identifier"
  @type server_key :: Transactions.Server.Key.t

  @doc """
  Starts the transaction process hierarchy.
  """
  def start_link() do
    children = [
      registry_spec(),
      supervisor(Sippet.Transactions.Supervisor, [])
    ]

    options = [strategy: :one_for_one, name: __MODULE__]

    Supervisor.start_link(children, options)
  end

  defdelegate start_client(transaction, outgoing_request),
    to: Sippet.Transactions.Supervisor

  defdelegate start_server(transaction, incoming_request),
    to: Sippet.Transactions.Supervisor

  @doc """
  Receives a message from the transport.

  If the message is a request, then it will look if a server transaction
  already exists for it and redirect to it. Otherwise, if the request method
  is `:ack`, it will redirect the request directly to `Sippet.Core`; if not
  `:ack`, then a new `Sippet.Transactions.Server` will be created.

  If the message is a response, it looks if a client transaction already exists
  in order to handle it, and if so, redirects to it. Otherwise the response is
  redirected directly to the `Sippet.Core`. The latter is done so because of
  the usual SIP behavior or handling the 200 OK response retransmissions for
  requests with `:invite` method directly.

  When receiving a burst of equivalent requests, it is possible that another
  entity has already created the server transaction, and then the function
  will return a `{:error, reason}` tuple.

  In case of success, returns `:ok`.
  """
  @spec receive_message(request | response) :: :ok | {:error, reason}
  def receive_message(
      %Message{start_line: %RequestLine{}} = incoming_request) do
    transaction = Transactions.Server.Key.new(incoming_request)

    case lookup(transaction) do
      [{_sup, pid}] ->
        # Redirect the request to the existing transaction. These are tipically
        # retransmissions or ACKs for 200 OK responses.
        Transactions.Server.receive_request(pid, incoming_request)
      [] ->
        if incoming_request.start_line.method == :ack do
          # Redirect to the core directly. ACKs sent out of transactions
          # pertain to the core.
          Core.receive_request(incoming_request, nil)
        else
          # Start a new server transaction now. The transaction will redirect
          # to the core once it starts. It will return errors only if there was
          # some kind of race condition when receiving the request.
          case start_server(transaction, incoming_request) do
            {:ok, _} -> :ok
            {:ok, _, _} -> :ok
            _errors -> {:error, :already_started}
          end
        end
    end
  end

  def receive_message(
      %Message{start_line: %StatusLine{}} = incoming_response) do
    transaction = Transactions.Client.Key.new(incoming_response)

    case lookup(transaction) do
      [{_sup, pid}] ->
        # Redirect the response to the existing client transaction. If needed,
        # the client transaction will redirect to the core from there.
        Transactions.Client.receive_response(pid, incoming_response)
      [] ->
        # Redirect the response to core. These are tipically retransmissions of
        # 200 OK for sent INVITE requests, and they have to be handled directly
        # by the core in order to catch the correct media handling.
        Core.receive_response(incoming_response, nil)
    end
  end

  @doc """
  Sends a request using client transactions.

  Requests of method `:ack` shall be sent directly to `Sippet.Transports`. If
  an `:ack` request is detected, it returns `{:error, :not_allowed}`.

  A `Sippet.Transactions.Client` is created to handle retransmissions, when the
  transport presumes it, and match response retransmissions, so the
  `Sippet.Core` doesn't get retransmissions other than 200 OK for `:invite`
  requests.

  In case of success, returns `:ok`.
  """
  @spec send_request(request) :: :ok | {:error, reason}
  def send_request(%Message{start_line: %RequestLine{method: :ack}}) do
    # ACKs should be sent directly to transport.
    Logger.error("ACKs are not allowed to use transactions")
    {:error, :not_allowed}
  end

  def send_request(%Message{start_line: %RequestLine{}} = outgoing_request) do
    transaction = Transactions.Client.Key.new(outgoing_request)

    # Create a new client transaction now. The request is passed to the
    # transport once it starts.
    case start_client(transaction, outgoing_request) do
      {:ok, _} -> {:ok, transaction}
      {:ok, _, _} -> {:ok, transaction}
      _errors ->
        Logger.warn fn ->
          "client transaction #{transaction} already exists"
        end
        {:error, :already_started}
    end
  end

  @doc """
  Sends a response to a server transaction.

  The server transaction identifier is obtained from the message attributes.

  See `send_response/2`.
  """
  @spec send_response(response) :: :ok | {:error, reason}
  def send_response(%Message{start_line: %StatusLine{}} = outgoing_response) do
    server_transaction = Transactions.Server.Key.new(outgoing_response)
    send_response(server_transaction, outgoing_response)
  end

  @doc """
  Sends a response to a server transaction.

  Server transactions are created when the incoming request is received, see
  `receive_message/1`. The first parameter `server_transaction` indicates the
  reference passed to `Sippet.Core` when the request is received.

  If there is no such server transaction, returns `{:error, :no_transaction}`.

  In case of success, returns `:ok`.
  """
  @spec send_response(server_key, response) :: :ok | {:error, reason}
  def send_response(%Transactions.Server.Key{} = server_key,
      %Message{start_line: %StatusLine{}} = outgoing_response) do
    case lookup(server_key) do
      [{_sup, pid}] ->
        # Send the response through the existing server transaction.
        Transactions.Server.send_response(pid, outgoing_response)
      [] ->
        {:error, :no_transaction}
    end
  end

  @doc """
  Receives a transport error.

  The client and server identifiers are passed to the transport by the
  transactions. If the transport faces an error, it has to inform the
  transaction using this function.
  """
  @spec receive_error(client_key | server_key, reason) :: :ok
  def receive_error(key, reason) do
    case lookup(key) do
      [{_sup, pid}] ->
        # Send the response through the existing server key.
        case key do
          %Transactions.Client.Key{} ->
            Transactions.Client.receive_error(pid, reason)
          %Transactions.Server.Key{} ->
            Transactions.Server.receive_error(pid, reason)
        end
      [] ->
        case key do
          %Transactions.Client.Key{} ->
            Logger.warn fn ->
              "client key #{key} not found"
            end
          %Transactions.Server.Key{} ->
            Logger.warn fn ->
              "server key #{key} not found"
            end
        end
        {:error, :no_key}
    end
  end
end
