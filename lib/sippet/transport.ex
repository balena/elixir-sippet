defmodule Sippet.Transport.Plug do
  @moduledoc """
  A behaviour module for implementing a listening socket.
  """

  @type local :: [{:address, address :: binary}]

  @type watermark :: [{:low, integer} | {:high, integer}]

  @type version :: 4 | 6

  @type sock_opts :: [sock_opt]
  @type sock_opt ::
    {:local, local} |
    {:backlog, integer} |
    {:watermark, watermark} |
    {:version, version}

  @type listen_port :: :inet.port_number

  @type options :: GenServer.options

  @type on_start :: GenServer.on_start

  @doc """
  Starts a child process connected to the given destination.
  """
  @callback start_link(listen_port, sock_opts, options) :: on_start

  @doc """
  Whether this transport is reliable (stream-based).
  """
  @callback reliable?() :: boolean
end

defmodule Sippet.Transport.Conn do
  @moduledoc """
  A behaviour module for implementing a transport connection.

  This module defines the behavior all transport connections have to implement.
  """

  @type conn :: pid

  @type transaction :: pid | nil

  @type message :: %Sippet.Message{}

  @type host_and_port :: {String.t, integer}

  @type options :: GenServer.options

  @type on_start :: GenServer.on_start

  @doc """
  Starts a child process connected to the given destination.
  """
  @callback start_link(host_and_port, options) :: on_start

  @doc """
  Sends a message to the given transport. If any error occur while sending the
  message, and the transaction is not `nil`, the transaction should be informed
  so by calling `error/2`.
  """
  @callback send_message(conn, message, transaction) :: :ok

  defmacro __using__(_opts) do
    quote location: :keep do

      alias Sippet.Transaction, as: Transaction

      @doc false
      def receive_message(message),
        do: Transaction.Registry.receive_message(message)

      @doc false
      def error(reason, transaction)
          when is_atom(reason) and is_pid(transaction) do
        Transaction.on_error(transaction, reason)
      end
    end
  end
end

defmodule Sippet.Transport.Registry do
  import Supervisor.Spec
  alias Sippet.Message, as: Message

  def start_link() do
    partitions = System.schedulers_online()

    children = [
      supervisor(Registry, [:unique, __MODULE__, partitions: partitions]) |
      do_get_children()
    ]

    args = [strategy: :one_for_one]
    {:ok, sup_id} = Supervisor.start_link(children, args)

    Registry.register(__MODULE__, :supervisor, sup_id)

    {:ok, sup_id}
  end

  defp do_get_children() do
    Application.get_env(:sippet, __MODULE__)
    |> Map.to_list()
    |> do_get_children([])
  end

  defp do_get_children([], result), do: result
  defp do_get_children([head|rest], result) do
    {protocol, {{plug_module, _conn_module}, [port, sock_opts]}} = head
    name = {:via, Registry, {:plug, protocol}}
    options = [restart: :transient]
    child_spec = worker(plug_module, [port, sock_opts, [name: name]], options)
    do_get_children(rest, [child_spec | result])
  end

  def send(transaction \\ nil, %Message{} = message) do
    {protocol, host, port} = do_get_destination(message)
    {conn_module, conn} = get_connection(protocol, host, port)
    apply(conn_module, :send, [conn, message, transaction])
  end

  defp do_get_destination(%Message{headers: %{via: via}} = message) do
    {_version, protocol, {host, port}, params} = List.last(via)
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

      {protocol, host, port}
    else
      {protocol, host, port}
    end
  end

  def get_connection(protocol, host, port) do
    name = {:conn, protocol, host, port}
    {{_plug_module, conn_module}, _args} =
      Application.get_env(:sippet, __MODULE__)
      |> Map.get(protocol)

    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, conn}] ->
        {conn_module, conn}
      [] ->
        [{_parent_id, sup_id}] = Registry.lookup(__MODULE__, :supervisor)
        name = {:via, Registry, name}
        options = [restart: :transient]
        child_spec = worker(conn_module, [{host, port}, [name: name]], options)
        conn =
          case Supervisor.start_child(sup_id, child_spec) do
            {:ok, conn, _info} -> conn
            {:ok, conn} -> conn
          end

        {conn_module, conn}
    end
  end

  def reliable?(%Message{headers: %{via: via}}) do
    {_version, protocol, _host_and_port, _params} = List.last(via)

    {{plug_module, _conn_module}, _args} =
      Application.get_env(:sippet, __MODULE__)
      |> Map.get(protocol)

    apply(plug_module, :reliable?)
  end
end
