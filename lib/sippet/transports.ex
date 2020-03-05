defmodule Sippet.Transports do
  @moduledoc """
  The `Sippet.Transports` is responsible for the actual transmission of requests
  and responses over network transports.

  Network transport protocols should be registered during initialization:

      def init(_) do
        Sippet.Transports.register_transport(:udp, false)
        ...
      end

  Messages are dispatched to transports by sending the following message:

      send(pid, {:send_message, message, host, port, transaction})

  Whenever a message is received by a transport, the
  `Sippet.Transports.Receiver` should be used to process, validate and route
  messages through the transaction layer or send directly to the core.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.URI, as: URI

  require Logger

  @doc false
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  @doc """
  Starts the transport registry.
  """
  @spec start_link() :: {:ok, pid} | {:error, term}
  def start_link(),
    do: Registry.start_link(keys: :unique, name: __MODULE__.Registry)

  @doc """
  Registers a transport for a given protocol.
  """
  @spec register_transport(atom, boolean) :: :ok | {:error, :already_registered}
  def register_transport(protocol, reliable)
      when is_atom(protocol) and is_boolean(reliable) do
    case Registry.register(__MODULE__.Registry, protocol, reliable) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, _}} ->
        {:error, :already_registered}
    end
  end

  @doc """
  Sends a message to the network.

  If specified, the `transaction` will receive the transport error if occurs.
  See `Sippet.Transactions.receive_error/2`.
  """
  @spec send_message(Message.t, GenServer.server | nil) :: :ok
  def send_message(message, transaction \\ nil) do
    {protocol, host, port} = get_destination(message)
    case Registry.lookup(__MODULE__.Registry, protocol) do
      [{pid, _}] ->
        send(pid, {:send_message, message, host, port, transaction})

        :ok

      _ ->
        raise ArgumentError, message: "protocol not registered"
    end
  end

  defp get_destination(%Message{target: target}) when is_tuple(target),
    do: target

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
            %{"rport" => ""} -> port
            %{"rport" => rport} -> rport |> String.to_integer()
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
        {_version, protocol, _sent_by, _params} =
          hd(request.headers.via)
        protocol
      end

    {protocol, host, port}
  end

  @doc """
  Verifies if the transport protocol used to send the given message is
  reliable.
  """
  @spec reliable?(Message.t) :: boolean
  def reliable?(%Message{headers: %{via: via}}) do
    {_version, protocol, _host_and_port, _params} = hd(via)
    case Registry.lookup(__MODULE__.Registry, protocol) do
      [{_, reliable}] ->
        reliable

      _ ->
        raise ArgumentError, message: "protocol not registered"
    end
  end
end
