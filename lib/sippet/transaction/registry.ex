defmodule Sippet.Transaction.Registry do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  require Logger

  def receive_message(%Message{start_line: %RequestLine{}} = request) do
    name = incoming_message_name(request)

    case Registry.lookup(__MODULE__, name) do
      [{_sup, transaction}] ->
        # Redirect the request to the existing transaction. These are tipically
        # retransmissions or ACKs for 200 OK responses.
        Sippet.ServerTransaction.receive_request(transaction, request)
      [] ->
        if request.start_line.method == :ack do
          # Redirect to the core directly. ACKs sent out of transactions
          # pertain to the core.
          core = Application.get_env(:sippet, :core)
          apply(core, :receive_request, [request, nil])
        else
          # Start a new server transaction now. The transaction will redirect
          # to the core once it starts.
          case Sippet.Transaction.Supervisor.start_server(request) do
            {:ok, _} -> :ok
            {:ok, _, _} -> :ok
            other -> other
          end
        end
    end
  end

  def receive_message(%Message{start_line: %StatusLine{}} = response) do
    name = incoming_message_name(response)

    case Registry.lookup(__MODULE__, name) do
      [{_sup, transaction}] ->
        # Redirect the response to the existing client transaction. If needed,
        # the client transaction will redirect to the core from there.
        Sippet.ClientTransaction.receive_response(transaction, response)
      [] ->
        # Redirect the response to core. These are tipically retransmissions of
        # 200 OK for sent INVITE requests, and they have to be handled directly
        # by the core in order to catch the correct media handling.
        core = Application.get_env(:sippet, :core)
        apply(core, :receive_response, [response, nil])
    end
  end

  defp incoming_message_name(%Message{start_line: %RequestLine{}} = request) do
    method =
      case request.start_line.method do
        :ack -> :invite
        other -> other
      end

    module =
      case method do
        :invite ->
          Sippet.Transaction.ClientTransaction.Invite
        _otherwise ->
          Sippet.Transaction.ClientTransaction.NonInvite
      end

    # Take the topmost via branch
    {_version, _protocol, sent_by, %{"branch" => branch}} =
      List.first(request.headers.via)

    {module, branch, sent_by, method}
  end

  defp incoming_message_name(%Message{start_line: %StatusLine{}} = response) do
    {_sequence, method} = response.headers.cseq

    module =
      case method do
        :invite ->
          Sippet.Transaction.ClientTransaction.Invite
        _otherwise ->
          Sippet.Transaction.ClientTransaction.NonInvite
      end

    # Take the topmost via branch
    {_version, _protocol, _sent_by, %{"branch" => branch}} =
      List.first(response.headers.via)

    {module, branch, method}
  end

  def send_request(%Message{start_line: %RequestLine{method: :ack}}) do
    # ACKs should be sent directly to transport.
    Logger.error("ACKs are not allowed to use transactions")
    {:error, :not_allowed}
  end

  def send_request(%Message{start_line: %RequestLine{}} = request) do
    name = outgoing_message_name(request)
    case Registry.lookup(__MODULE__, name) do
      [{_sup, _transaction}] ->
        # The only way for sending a request while the transaction still exists
        # is when the core did not reset a new Via header (therefore creating a
        # new branch).
        Logger.warn("transaction #{inspect name} already exists")
        {:error, :duplicated}
      [] ->
        # Create a new client transaction now. The request is passed to the
        # transport once it starts.
        case Sippet.Transaction.Supervisor.start_client(name, request) do
          {:ok, _} -> {:ok, name}
          {:ok, _, _} -> {:ok, name}
          other -> other
        end
    end
  end

  def send_response(%Message{start_line: %StatusLine{}} = response) do
    name = outgoing_message_name(response)
    case Registry.lookup(__MODULE__, name) do
      [{_sup, transaction}] ->
        # Send the response through the existing server transaction.
        Sippet.ServerTransaction.send_response(transaction, response)
        {:ok, name}
      [] ->
        Logger.warn("transaction #{inspect name} does not exist")
        {:error, :no_transaction}
    end
  end

  defp outgoing_message_name(%Message{start_line: %RequestLine{}} = request) do
    method = request.start_line.method

    module =
      case method do
        :invite ->
          Sippet.Transaction.ClientTransaction.Invite
        _otherwise ->
          Sippet.Transaction.ClientTransaction.NonInvite
      end

    # Take the topmost via branch
    {_version, _protocol, _sent_by, %{"branch" => branch}} =
      List.first(request.headers.via)

    {module, branch, method}
  end

  defp outgoing_message_name(%Message{start_line: %StatusLine{}} = response) do
    method = response.start_line.method

    module =
      case method do
        :invite ->
          Sippet.Transaction.ServerTransaction.Invite
        _otherwise ->
          Sippet.Transaction.ServerTransaction.NonInvite
      end

    # Take the topmost via sent-by and branch
    {_version, _protocol, sent_by, %{"branch" => branch}} =
      List.first(response.headers.via)

    {module, branch, sent_by, method}
  end
end
