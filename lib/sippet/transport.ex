defmodule Sippet.Transport do
  import Supervisor.Spec

  alias Sippet.Message, as: Message
  alias Sippet.Transport.Conn, as: Conn

  @doc """
  Starts the transport process hierarchy.
  """
  @spec start_link() :: Supervisor.on_start
  def start_link() do
    children =
      [Sippet.Transport.Registry.spec()] ++
      plugs_spec() ++
      conns_sup_spec()

    options = [
      strategy: :one_for_one,
      name: __MODULE__
    ]

    Supervisor.start_link(children, options)
  end

  defp plugs_spec() do
    Application.get_env(:sippet, __MODULE__)
    |> Keyword.fetch!(:plugs)
    |> plugs_spec([])
  end

  defp plugs_spec([], result), do: result
  defp plugs_spec([module | rest], result),
    do: plugs_spec(rest, [worker(module, []) | result])

  defp conns_sup_spec() do
    Application.get_env(:sippet, __MODULE__)
    |> Keyword.fetch!(:conns)
    |> conns_sup_spec([])
  end

  defp conns_sup_spec([], result), do: result
  defp conns_sup_spec([{protocol, _module} | rest], result),
    do: conns_sup_spec(rest, [supervisor(Conn, [protocol]) | result])

  @doc """
  Sends a message to the network.

  If specified, the `transaction` will receive errors, if they happen. See
  `Sippet.Transaction.receive_error/2`.
  """
  def send_message(message, transaction \\ nil) do
    {protocol, host, port} = get_destination(message)
    case Conn.start_connection(protocol, host, port, message, transaction) do
      {:ok, _server} ->
        :ok
      {:error, {:already_started, server}} ->
        Conn.send_message(server, message, transaction)
      _otherwise ->
        {:error, :unexpected}
    end
  end
  
  defp get_destination(%Message{headers: %{via: via}} = message) do
    {_version, protocol, {host, port}, params} = List.first(via)
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

    {protocol, host, port}
  end

  @doc """
  Verifies if the transport protocol used to send the given message is
  reliable.
  """
  def reliable?(%Message{headers: %{via: via}}) do
    {_version, protocol, _host_and_port, _params} = List.first(via)
    Conn.reliable?(protocol)
  end
end
