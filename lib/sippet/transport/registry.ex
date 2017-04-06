defmodule Sippet.Transport.Registry do
  alias Sippet.Message, as: Message

  def send(transaction \\ nil, %Message{} = msg) do
    {protocol, host, port} = do_get_destination(msg)
    module = do_get_conn_module(protocol)
    do_ensure_connection(module, host, port)
    Sippet.Transport.Conn.send_message(module, host, port, msg, transaction)
  end

  defp do_get_destination(%Message{headers: %{via: via}} = message) do
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

    {protocol, host, port}
  end

  defp do_get_conn_module(protocol) do
    Application.get_env(:sippet, __MODULE__) |> Map.fetch!(protocol)
  end

  defp do_ensure_connection(module, host, port) do
    case Registry.lookup(__MODULE__, {module, host, port}) do
      [{_parent, _child}] ->
        :ok
      [] ->
        {:ok, _child} =
          module
          |> Sippet.Transport.Conn.Supervisor.start_child(host, port)
        :ok
    end
  end

  def reliable?(%Message{headers: %{via: via}}) do
    {_version, protocol, _host_and_port, _params} = List.last(via)

    module = do_get_conn_module(protocol)
    apply(module, :reliable?)
  end
end
