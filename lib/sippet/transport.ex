defmodule Sippet.Transport do
  import Supervisor.Spec

  alias Sippet.Message, as: Message

  @doc """
  Starts the transport process hierarchy.
  """
  @spec start_link() :: Supervisor.on_start
  def start_link() do
    plug_conn_modules = Application.get_env(:sippet, __MODULE__)

    partitions = System.schedulers_online()
    options = [:unique, Sippet.Transport, [partitions: partitions]]
    registry_spec = supervisor(Registry, options)

    children = children_spec(plug_conn_modules, [registry_spec])

    options = [
      strategy: :one_for_one,
      name: __MODULE__
    ]

    Supervisor.start_link(children, options)
  end

  defp children_spec([], result), do: Enum.reverse(result)
  defp children_spec([{plug_module, conn_module}|rest], result) do
    new_result = [
      worker(plug_module, []),
      supervisor(__MODULE__, [conn_module])
      | result
    ]
    children_spec(rest, new_result)
  end

  @doc """
  Starts a supervisor responsible for connections.

  This function is called from the `start_link/0` function and it is not
  intended to be used alone.
  """
  @spec start_link(module) :: Supervisor.on_start
  def start_link(module) do
    children = [
      worker(module, [], restart: :transient)
    ]

    options = [
      strategy: :simple_one_for_one,
      name: via_tuple(module)
    ]

    Supervisor.start_link(children, options)
  end

  defp via_tuple(module) do
    {:via, Registry, {__MODULE__, module}}
  end

  @doc """
  Sends a message to the network.

  If specified, the `transaction` will receive errors, if they happen. See
  `Sippet.Transaction.receive_error/2`.
  """
  def send_message(%Message{} = message, transaction \\ nil) do
    {module, host, port} = get_destination(message)
    server =
      case ensure_connection(module, host, port) do
        {:ok, server} ->
          server
        {:error, {:already_started, server}} ->
          server
        _otherwise ->
          {:error, :unexpected}
      end

    case server do
      {:error, reason} ->
        {:error, reason}
      server ->
        Sippet.Transport.Conn.send_message(server, message, transaction)
    end
  end

  defp ensure_connection(module, host, port) do
    name = via_tuple(module)
    child_name = {module, host, port}
    Supervisor.start_child(name, [host, port, [name: child_name]])
  end
  
  defp get_destination(%Message{headers: %{via: via}} = message) do
    {_version, protocol, {host, port}, params} = List.last(via)
    {host, port} =
      if Message.response?(message) do
        host =
          case params do
            %{"received" => received} -> received
            _otherwise -> host
          end

        port =
          case params do
            %{"rport" => rport} -> Integer.parse(rport)
            _otherwise -> port
          end

        {host, port}
      else
        {host, port}
      end

    {get_connection_module(protocol), host, port}
  end

  defp get_connection_module(protocol) do
    Application.get_env(:sippet, __MODULE__) |> Keyword.fetch!(protocol)
  end

  @doc """
  Verifies if the transport protocol used to send the given message is
  reliable.
  """
  def reliable?(%Message{headers: %{via: via}}) do
    {_version, protocol, _host_and_port, _params} = List.first(via)
    get_connection_module(protocol) |> apply(:reliable?, [])
  end
end
