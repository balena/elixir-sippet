defmodule Sippet.Transaction.Registry do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.ClientTransaction, as: ClientTransaction
  alias Sippet.ServerTransaction, as: ServerTransaction

  require Logger

  def start_link() do
    schedulers_online = System.schedulers_online()
    Registry.start_link(:unique, __MODULE__,
                        partitions: schedulers_online)
  end

  def receive_message(%Message{headers: %{via: via}} = message) do
    {_version, _protocol, _host_and_port, params} = List.last(via)
    name = params |> Map.get("branch")
    do_receive_message(name, message)
  end

  defp do_receive_message(name,
      %Message{start_line: %RequestLine{method: method}} = request) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, transaction}] ->
        # Redirect the request to the existing transaction. These are tipically
        # retransmissions or ACKs for 200 OK responses.
        ServerTransaction.on_request(transaction, request)
      [] ->
        if method == :ack do
          # Redirect to the core directly. ACKs sent out of transactions
          # pertain to the core.
          core = Application.get_env(:sippet, :core)
          apply(core, :on_request, [request, nil])
        else
          # Start a new server transaction now. The transaction will redirect
          # to the core once it starts.
          module = ServerTransaction.get_module(request)
          opts = [name: via_tuple(module, name)]
          {:ok, _pid} = apply(module, :start_link, [request, opts])
        end
    end
    :ok
  end

  defp do_receive_message(name,
      %Message{start_line: %StatusLine{}} = response) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, transaction}] ->
        # Redirect the response to the existing client transaction. If needed,
        # the client transaction will redirect to the core from there.
        ClientTransaction.on_response(transaction, response)
      [] ->
        # Redirect the response to core. These are tipically retransmissions of
        # 200 OK for sent INVITE requests, and they have to be handled directly
        # by the core in order to catch the correct media handling.
        core = Application.get_env(:sippet, :core)
        apply(core, :on_response, [response, nil])
    end
    :ok
  end

  defp via_tuple(module, name), do: {:via, Registry, {module, name}}

  def send_message(%Message{headers: %{via: via}} = message) do
    {_version, _protocol, _host_and_port, params} = List.last(via)
    name = params |> Map.get("branch")
    do_send_message(name, message)
  end

  def do_send_message(_name,
      %Message{start_line: %RequestLine{method: :ack}}) do
    # ACKs should be sent directly to transport.
    Logger.error("ACKs are not allowed to be sent using transactions")
    {:error, :not_allowed}
  end

  def do_send_message(name,
      %Message{start_line: %RequestLine{}} = request) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, _transaction}] ->
        # The only way for sending a request while the transaction still exists
        # is when the core did not reset a new Via header (therefore creating a
        # new branch).
        Logger.warn("transaction #{inspect name} already exists")
        {:error, :duplicated}
      [] ->
        # Create a new client transaction now. The request is passed to the
        # transport once it starts.
        module = ClientTransaction.get_module(request)
        opts = [name: via_tuple(module, name)]
        {:ok, _pid} = apply(module, :start_link, [request, opts])
        :ok
    end
  end

  def do_send_message(name,
      %Message{start_line: %StatusLine{}} = response) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, transaction}] ->
        # Send the response through the existing server transaction.
        ServerTransaction.send_response(transaction, response)
        :ok
      [] ->
        Logger.warn("transaction #{inspect name} does not exist")
        {:error, :no_transaction}
    end
  end
end
