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

  def receive(%Message{headers: %{via: via}} = message) do
    name = List.first(via) |> elem(3) |> Map.get("branch")
    do_receive(name, message)
  end

  defp do_receive(name,
      %Message{start_line: %RequestLine{method: method}} = request) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, child_pid}] ->
        ServerTransaction.on_request(child_pid, request)
      [] ->
        if method == :ack do
          core = Application.get_env(:sippet, :core)
          apply(core, :on_request, [request, nil])
        else
          module = ServerTransaction.get_module(request)
          opts = [name: via_tuple(module, name)]
          {:ok, _pid} = apply(module, :start_link, [request, opts])
        end
    end
    :ok
  end

  defp do_receive(name,
      %Message{start_line: %StatusLine{}} = response) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, child_pid}] ->
        ClientTransaction.on_response(child_pid, response)
        :ok
      [] ->
        Logger.warn("unhandled transport response to transaction " <>
                    "#{inspect name}")
        {:error, :no_route}
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
    Transport.Registry.send(ack)
  end

  def do_send(name,
      %Message{start_line: %RequestLine{}} = request) do
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, _child_pid}] ->
        Logger.warn("transaction #{inspect name} already exists")
        {:error, :duplicated}
      [] ->
        module = ClientTransaction.get_module(request)
        opts = [name: via_tuple(module, name)]
        {:ok, _pid} = apply(module, :start_link, [request, opts])
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
        {:error, :no_route}
    end
  end
end
