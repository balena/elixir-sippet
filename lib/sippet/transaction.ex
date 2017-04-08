defmodule Sippet.Transaction do
  @moduledoc """
  The `Sippet.Transaction` is responsible to dispatch messages from
  `Sippet.Transport` and `Sippet.Core` modules to transactions, creating when
  necessary.
  """

  import Supervisor.Spec

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transaction, as: Transaction
  alias Sippet.Core, as: Core

  require Logger

  @type request :: Message.request
  @type response :: Message.response
  @type reason :: atom
  @type client_transaction :: Transaction.Client.t
  @type server_transaction :: Transaction.Server.t

  @doc """
  Starts the transaction process hierarchy.
  """
  def start_link() do
    partitions = [partitions: System.schedulers_online()]
    registry_args = [:unique, __MODULE__, partitions]
    registry_spec = supervisor(Registry, registry_args)

    sup_children = [worker(GenStateMachine, [], restart: :transient)]
    sup_opts = [strategy: :simple_one_for_one, name: __MODULE__]
    sup_spec = worker(Supervisor, [sup_children, sup_opts])

    options = [strategy: :one_for_one]

    Supervisor.start_link([registry_spec, sup_spec], options)
  end

  @doc """
  Starts a client transaction.
  """
  @spec start_client(Transaction.Client.t, request) ::
    Supervisor.on_start_child
  def start_client(%Transaction.Client{} = transaction,
      %Message{start_line: %RequestLine{}} = outgoing_request) do
    module =
      case transaction.method do
        :invite -> Transaction.Client.Invite
        _otherwise -> Transaction.Client.NonInvite
      end

    initial_data = Transaction.Client.State.new(outgoing_request, transaction)
    Supervisor.start_child(__MODULE__, [module, initial_data,
                           [name: transaction]])
  end

  @doc """
  Starts a server transaction.
  """
  @spec start_server(Transaction.Server.t, request) ::
    Supervisor.on_start_child
  def start_server(%Transaction.Server{} = transaction,
      %Message{start_line: %RequestLine{}} = incoming_request) do
    module =
      case transaction.method do
        :invite -> Transaction.Server.Invite
        _otherwise -> Transaction.Server.NonInvite
      end

    initial_data = Transaction.Server.State.new(incoming_request, transaction)
    Supervisor.start_child(__MODULE__, [module, initial_data,
                           [name: transaction]])
  end

  @doc """
  Receives a message from the transport.

  If the message is a request, then it will look if a server transaction
  already exists for it and redirect to it. Otherwise, if the request method
  is `:ack`, it will redirect the request directly to `Sippet.Core`; if not
  `:ack`, then a new `Sippet.Transaction.Server` will be created.

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
    transaction = Transaction.Server.new(incoming_request)

    case Registry.lookup(__MODULE__, transaction) do
      [{_sup, pid}] ->
        # Redirect the request to the existing transaction. These are tipically
        # retransmissions or ACKs for 200 OK responses.
        Transaction.Server.receive_request(pid, incoming_request)
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
    transaction = Transaction.Client.new(incoming_response)

    case Registry.lookup(__MODULE__, transaction) do
      [{_sup, pid}] ->
        # Redirect the response to the existing client transaction. If needed,
        # the client transaction will redirect to the core from there.
        Transaction.Client.receive_response(pid, incoming_response)
      [] ->
        # Redirect the response to core. These are tipically retransmissions of
        # 200 OK for sent INVITE requests, and they have to be handled directly
        # by the core in order to catch the correct media handling.
        Core.receive_response(incoming_response, nil)
    end
  end

  @doc """
  Sends a request using client transactions.

  Requests of method `:ack` shall be sent directly to `Sippet.Transport`. If an
  `:ack` request is detected, it returns `{:error, :not_allowed}`.

  A `Sippet.Transaction.Client` is created to handle retransmissions, when the
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
    transaction = Transaction.Client.new(outgoing_request)

    # Create a new client transaction now. The request is passed to the
    # transport once it starts.
    case start_client(transaction, outgoing_request) do
      {:ok, _} -> {:ok, transaction}
      {:ok, _, _} -> {:ok, transaction}
      _errors ->
        Logger.warn("client transaction #{transaction} already exists")
        {:error, :already_started}
    end
  end

  @doc """
  Sends a response to a server transaction.

  Server transactions are created when the incoming request is received, see
  `receive_message/1`. The first parameter `server_transaction` indicates the
  reference passed to `Sippet.Core` when the request is received.

  If there is no such server transaction, returns `{:error, :no_transaction}`.

  In case of success, returns `:ok`.
  """
  @spec send_response(server_transaction, response) :: :ok | {:error, reason}
  def send_response(%Transaction.Server{} = server_transaction,
      %Message{start_line: %StatusLine{}} = outgoing_response) do
    case Registry.lookup(__MODULE__, server_transaction) do
      [{_sup, pid}] ->
        # Send the response through the existing server transaction.
        Transaction.Server.send_response(pid, outgoing_response)
      [] ->
        Logger.warn("server transaction #{server_transaction} not found")
        {:error, :no_transaction}
    end
  end

  @doc """
  Receives a transport error.

  The client and server identifiers are passed to the transport by the
  transactions. If the transport faces an error, it has to inform the
  transaction using this function.
  """
  @spec receive_error(client_transaction | server_transaction, reason) :: :ok
  def receive_error(transaction, reason) do
    case Registry.lookup(__MODULE__, transaction) do
      [{_sup, pid}] ->
        # Send the response through the existing server transaction.
        case transaction do
          %Transaction.Client{} ->
            Transaction.Client.receive_error(pid, reason)
          %Transaction.Server{} ->
            Transaction.Server.receive_error(pid, reason)
        end
      [] ->
        case transaction do
          %Transaction.Client{} ->
            Logger.warn("client transaction #{transaction} not found")
          %Transaction.Server{} ->
            Logger.warn("server transaction #{transaction} not found")
        end
        {:error, :no_transaction}
    end
  end
end
