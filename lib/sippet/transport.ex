defmodule Sippet.Transport do
  @moduledoc """
  The `Sippet.Transport` is responsible for the actual transmission of requests
  and responses over network transports.

  Network transport protocols are implemented following the
  `Sippet.Transport.Plug` behavior, and they are configured as:

      config :sippet, Sippet.Transport,
        udp: Sippet.Transport.UDP.Plug

  Whenever a message is received by a plug, the `Sippet.Transport.Queue` is
  used to process, validate and route it through the transaction layer or core.
  """

  import Supervisor.Spec

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transport.Pool, as: Pool
  alias Sippet.URI, as: URI

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
    Application.get_env(:sippet, __MODULE__, [])
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

  defp get_destination(%Message{target: target}) when is_tuple(target) do
    target
  end

  defp get_destination(%Message{start_line: %StatusLine{},
      headers: %{via: via}} = message) do
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

  defp get_destination(%Message{start_line:
      %RequestLine{request_uri: uri}} = request) do
    host = uri.host
    port = uri.port

    params = URI.decode_parameters(uri.parameters)
    protocol =
      if params |> Map.has_key?("transport") do
        case String.downcase(params["transport"]) do
          "dccp" -> :dccp
          "dtls" -> :dtls
          "sctp" -> :sctp
          "stomp" -> :stomp
          "tcp" -> :tcp
          "tls" -> :tls
          "udp" -> :udp
          "ws" -> :ws
          "wss" -> :wss
          other -> other
        end
      else
        {_version, protocol, _sent_by, _params} =
          hd(request.headers.via)
        protocol
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
