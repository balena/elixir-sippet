defmodule Sippet.Transports do
  @moduledoc """
  The `Sippet.Transports` is responsible for the actual transmission of requests
  and responses over network transports.

  Network transport protocols are implemented following the
  `Sippet.Transports.Plug` behavior, and they are configured as:

      config :sippet, Sippet.Transports,
        udp: Sippet.Transports.UDP.Plug

  Whenever a message is received by a plug, the `Sippet.Transports.Queue` is
  used to process, validate and route it through the transaction layer or core.
  """

  import Supervisor.Spec

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transports.Pool, as: Pool
  alias Sippet.URI, as: URI

  @doc """
  Starts the transport process hierarchy.
  """
  @spec start_link() :: Supervisor.on_start()
  def start_link() do
    children = [
      Pool.spec()
      | plugs_specs()
    ]

    options = [
      strategy: :one_for_one,
      name: __MODULE__
    ]

    Supervisor.start_link(children, options)
  end

  defp plugs_specs() do
    :sippet
    |> Application.get_env(__MODULE__, [])
    |> plugs_specs([])
  end

  defp plugs_specs([], result), do: result

  defp plugs_specs([{_protocol, module} | rest], result),
    do: plugs_specs(rest, [worker(module, []) | result])

  @doc """
  Sends a message to the network.

  If specified, the `transaction` will receive the transport error if occurs.
  See `Sippet.Transactions.receive_error/2`.

  This function may block the caller temporarily due to resource constraints.
  """
  @spec send_message(Message.t(), GenServer.server() | nil) :: :ok
  def send_message(message, transaction \\ nil) do
    {protocol, host, port} = get_destination(message)
    plug = protocol |> to_plug()
    apply(plug, :send_message, [message, host, port, transaction])
  end

  defp get_destination(%Message{target: target}) when is_tuple(target) do
    target
  end

  defp get_destination(%Message{start_line: %StatusLine{}, headers: %{via: via}} = message) do
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
            %{"rport" => ""} -> port
            %{"rport" => rport} -> Integer.parse(rport)
            _otherwise -> port
          end

        {host, port}
      else
        {host, port}
      end

    {protocol, host, port}
  end

  defp get_destination(%Message{start_line: %RequestLine{request_uri: uri}} = request) do
    host = uri.host
    port = uri.port

    params =
      if uri.parameters == nil do
        %{}
      else
        URI.decode_parameters(uri.parameters)
      end

    protocol =
      if params |> Map.has_key?("transport") do
        Sippet.Message.to_protocol(params["transport"])
      else
        {_version, protocol, _sent_by, _params} = hd(request.headers.via)
        protocol
      end

    {protocol, host, port}
  end

  defp to_plug(protocol) do
    :sippet
    |> Application.get_env(Sippet.Transports)
    |> Keyword.fetch!(protocol)
  end

  @doc """
  Verifies if the transport protocol used to send the given message is
  reliable.
  """
  @spec reliable?(Message.t()) :: boolean
  def reliable?(%Message{headers: %{via: via}}) do
    {_version, protocol, _host_and_port, _params} = hd(via)
    plug = protocol |> to_plug()
    apply(plug, :reliable?, [])
  end
end
