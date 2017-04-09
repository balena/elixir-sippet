defmodule Sippet.Transport do
  import Supervisor.Spec

  alias Sippet.Message, as: Message
  alias Sippet.Transport.Pool, as: Pool

  @doc """
  Starts the transport process hierarchy.
  """
  @spec start_link() :: Supervisor.on_start
  def start_link() do
    children = [
      Pool.spec() |
      plugs_specs()
    ]

    options = [
      strategy: :one_for_one,
      name: __MODULE__
    ]

    Supervisor.start_link(children, options)
  end

  defp plugs_specs() do
    Application.get_env(:sippet, __MODULE__)
    |> plugs_specs([])
  end

  defp plugs_specs([], result), do: result
  defp plugs_specs([{_protocol, module} | rest], result),
    do: plugs_specs(rest, [worker(module, []) | result])

  @doc """
  Sends a message to the network.

  If specified, the `transaction` will receive the transport error if occurs.
  See `Sippet.Transaction.receive_error/2`.

  This function may block the caller temporarily due to resource constraints.
  """
  @spec send_message(Message.t, GenServer.server | nil) :: :ok
  def send_message(message, transaction \\ nil) do
    {protocol, host, port} = get_destination(message)
    plug = protocol |> to_plug()
    apply(plug, :send_message, [message, host, port, transaction])
  end

  defp get_destination(%Message{headers: %{via: via}} = message) do
    {_version, protocol, {host, port}, params} = hd(via)
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

  defp to_plug(protocol) do
    Application.get_env(:sippet, Sippet.Transport)
    |> Keyword.fetch!(protocol)
  end

  @doc """
  Verifies if the transport protocol used to send the given message is
  reliable.
  """
  @spec reliable?(Message.t) :: boolean
  def reliable?(%Message{headers: %{via: via}}) do
    {_version, protocol, _host_and_port, _params} = hd(via)
    plug = protocol |> to_plug()
    apply(plug, :reliable?, [])
  end
end
