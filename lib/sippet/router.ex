defmodule Sippet.Router do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.ClientTransaction, as: ClientTransaction
  alias Sippet.ServerTransaction, as: ServerTransaction
  alias Sippet.Transport, as: Transport

  require Logger

  def start_link() do
    schedulers_online = System.schedulers_online()
    Registry.start_link(:unique, __MODULE__,
                        partitions: schedulers_online)
  end

  def receive(transport,
      %Message{headers: %{via: via}} = message) do
    name = List.first(via) |> elem(3) |> Map.get("branch")
    do_receive(transport, name, message)
  end

  defp do_receive(transport, name,
      %Message{start_line: %RequestLine{method: method}} = request) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, child_pid}] ->
        ServerTransaction.on_request(child_pid, request)
      [] ->
        if method == :ack do
          core = Application.get_env(:sippet, :core)
          apply(core, :on_request, [request, nil])
        else
          module =
            case method do
              :invite -> ServerTransaction.Invite
              _other -> ServerTransaction.NonInvite
            end

          {:ok, _pid} = ServerTransaction.start_link(request, transport,
                                    name: via_tuple(module, name))
        end
        :ok
    end
  end

  defp do_receive(_transport, name,
      %Message{start_line: %StatusLine{}} = response) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, child_pid}] ->
        ClientTransaction.on_response(child_pid, response)
      [] ->
        Logger.warn("unhandled transport response to transaction " <>
                    "#{inspect name}")
        :ok
    end
  end

  defp via_tuple(module, name), do: {:via, Registry, {module, name}}

  def send(%Message{headers: %{via: via}} = message) do
    name = List.first(via) |> elem(3) |> Map.get("branch")
    do_send(name, message)
  end

  def do_send(_name,
      %Message{start_line: %RequestLine{method: :ack}} = ack) do
    # Route ACKs directly to transport.
    Transport.get_transport(ack) |> Transport.send(ack)
  end

  def do_send(name,
      %Message{start_line: %RequestLine{method: method}} = request) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, _child_pid}] ->
        Logger.warn("transaction #{inspect name} already exists")
        :ok
      [] ->
        module =
          case method do
            :invite -> ClientTransaction.Invite
            _other -> ClientTransaction.NonInvite
          end

        transport = Transport.get_transport(request)

        {:ok, _pid} = ClientTransaction.start_link(request, transport,
                                  name: via_tuple(module, name))
        :ok
    end
  end

  def do_send(name,
      %Message{start_line: %StatusLine{}} = response) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, child_pid}] ->
        ServerTransaction.send_response(child_pid, response)
        :ok
      [] ->
        Logger.warn("unhandled core response to transaction #{inspect name}")
        :ok
    end
  end
end
