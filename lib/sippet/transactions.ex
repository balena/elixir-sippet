defmodule Sippet.Transactions do
  @moduledoc """
  The `Sippet.Transactions` is responsible to dispatch messages from
  `Sippet.Transports` and `Sippet.Core` modules to transactions, creating when
  necessary.
  """

  import Supervisor.Spec

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
      supervisor(Sippet.Transactions.Registry, []),
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

    case Sippet.Transactions.Registry.lookup(transaction) do
      nil ->
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
      pid ->
        # Redirect the request to the existing transaction. These are tipically
        # retransmissions or ACKs for 200 OK responses.
        Transactions.Server.receive_request(pid, incoming_request)
    end
  end

  def receive_message(
      %Message{start_line: %StatusLine{}} = incoming_response) do
    transaction = Transactions.Client.Key.new(incoming_response)

    case Sippet.Transactions.Registry.lookup(transaction) do
      nil ->
        # Redirect the response to core. These are tipically retransmissions of
        # 200 OK for sent INVITE requests, and they have to be handled directly
        # by the core in order to catch the correct media handling.
        Core.receive_response(incoming_response, nil)
      pid ->
        # Redirect the response to the existing client transaction. If needed,
        # the client transaction will redirect to the core from there.
        Transactions.Client.receive_response(pid, incoming_response)
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
    server_key = Transactions.Server.Key.new(outgoing_response)
    send_response(outgoing_response, server_key)
  end

  @doc """
  Sends a response to a server transaction.

  Server transactions are created when the incoming request is received, see
  `receive_message/1`. The first parameter `server_key` indicates the reference
  passed to `Sippet.Core` when the request is received.

  If there is no such server transaction, returns `{:error, :no_transaction}`.

  In case of success, returns `:ok`.
  """
  @spec send_response(response, server_key) :: :ok | {:error, reason}
  def send_response(%Message{start_line: %StatusLine{}} = outgoing_response,
                    %Transactions.Server.Key{} = server_key) do
    case Sippet.Transactions.Registry.lookup(server_key) do
      nil ->
        {:error, :no_transaction}
      pid ->
        # Send the response through the existing server transaction.
        Transactions.Server.send_response(pid, outgoing_response)
    end
  end

  @doc """
  Receives a transport error.

  The client and server identifiers are passed to the transport by the
  transactions. If the transport faces an error, it has to inform the
  transaction using this function.

  If a transaction with such a key does not exist, it will be silently ignored.
  """
  @spec receive_error(client_key | server_key, reason) :: :ok
  def receive_error(key, reason) do
    case Sippet.Transactions.Registry.lookup(key) do
      nil ->
        case key do
          %Transactions.Client.Key{} ->
            Logger.warn fn ->
              "client key #{inspect key} not found"
            end
          %Transactions.Server.Key{} ->
            Logger.warn fn ->
              "server key #{inspect key} not found"
            end
        end
        :ok
      pid ->
        # Send the response through the existing server key.
        case key do
          %Transactions.Client.Key{} ->
            Transactions.Client.receive_error(pid, reason)
          %Transactions.Server.Key{} ->
            Transactions.Server.receive_error(pid, reason)
        end
    end
  end

  @doc """
  Terminates a client or server transaction forcefully.

  This function is not generally executed by entities; there is a single case
  where it is fundamental, which is when a client transaction is in proceeding
  state for a long time, and the transaction has to be finished forcibly, or it
  will never finish by itself.

  If a transaction with such a key does not exist, it will be silently ignored.
  """
  @spec terminate(client_key | server_key) :: :ok
  def terminate(key) do
    case Sippet.Transactions.Registry.lookup(key) do
      nil ->
        :ok
      pid ->
        # Send the response through the existing server key.
        case key do
          %Transactions.Client.Key{} ->
            Transactions.Client.terminate(pid)
          %Transactions.Server.Key{} ->
            Transactions.Server.terminate(pid)
        end
    end
  end

  @doc """
  Handles the sigil `~K`.

  It returns a client or server transaction key depending on the number of
  parameters passed.

  ## Examples

      iex> import Sippet.Transactions, only: [sigil_K: 2]

      iex> Sippet.Transactions.Client.Key.new("z9hG4bK230f2.1", :invite)
      ~K[z9hG4bK230f2.1|:invite]

      iex> ~K[z9hG4bK230f2.1|INVITE]
      ~K[z9hG4bK230f2.1|:invite]

      iex> Sippet.Transactions.Server.Key.new("z9hG4bK74b21", :invite, {"client.biloxi.example.com", 5060})
      ~K[z9hG4bK74b21|:invite|client.biloxi.example.com:5060]

      iex> ~K[z9hG4bK74b21|INVITE|client.biloxi.example.com:5060]
      ~K[z9hG4bK74b21|:invite|client.biloxi.example.com:5060]

  """
  def sigil_K(string, _) do
    case String.split(string, "|") do
      [branch, method] ->
        Transactions.Client.Key.new(branch, sigil_to_method(method))
      [branch, method, sentby] ->
        [host, port] = String.split(sentby, ":")
        Transactions.Server.Key.new(branch, sigil_to_method(method),
                                    {host, String.to_integer(port)})
    end
  end

  defp sigil_to_method(method) do
    case method do
      ":" <> rest -> Message.to_method(rest)
      other -> Message.to_method(other)
    end
  end
end
