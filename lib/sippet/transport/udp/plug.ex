defmodule Sippet.Transport.UDP.Plug do
  use GenServer
  use Sippet.Transport.Plug

  import Supervisor.Spec

  alias Sippet.Message, as: Message

  require Logger

  @doc """
  Starts the UDP plug.
  """
  def start_link() do
    port =
      Application.get_env(:sippet, __MODULE__)
      |> Keyword.fetch!(:port)

    if port <= 0 do
      raise ArgumentError, "invalid port #{inspect port}"
    end

    children = [
      worker(Agent, [fn -> %{} end, [name: agent_name()]]),
      worker(GenServer, [__MODULE__, port])
    ]

    options = [
      strategy: :one_for_one,
      name: __MODULE__
    ]

    Supervisor.start_link(children, options)
  end

  defp agent_name(), do: Module.concat(__MODULE__, Agent)

  def get_socket(),
    do: Agent.get(agent_name(), fn %{socket: socket} -> socket end)

  def init(port) do
    sock_opts = [as: :binary, mode: :active]

    socket = Socket.UDP.open!(port, sock_opts)
    Agent.update(agent_name(), &Map.put(&1, :socket, socket))

    {:ok, {address, _port}} = :inet.sockname(socket)

    Logger.info("started plug #{:inet.ntoa(address)}:#{port}/udp")
    {:ok, {socket, address, port}}
  end

  def handle_info({:udp, _socket, ip, from_port, packet},
      {_, address, port} = state) do
    case do_parse_message(packet) do
      {:ok, message} ->
        do_receive_message(message, ip, from_port)
      {:error, reason} ->
        Logger.error("couldn't parse incoming packet from " <>
                     "#{:inet.ntoa(address)}:#{port}: #{inspect reason}")
    end

    {:noreply, state}
  end

  def handle_info(msg, state),
    do: super(msg, state)

  defp do_parse_message(packet) do
    message = String.replace(packet, "\r\n", "\n")
    case String.split(message, "\n\n", parts: 2) do
      [header, body] ->
        do_parse_message(header <> "\n\n", body)
      [header] ->
        do_parse_message(header, "")
    end
  end

  defp do_parse_message(header, body) do
    case Message.parse(header) do
      {:ok, message} -> {:ok, %{message | body: body}}
      other -> other
    end
  end

  defp do_receive_message(message, ip, from_port) do
    if Message.response?(message) do
      host = to_string(:inet.ntoa(ip))

      message
      |> Message.update_header_back(:via, nil,
        fn({version, protocol, {via_host, via_port}, params}) ->
          params =
            if host != via_host do
              params |> Map.put("received", host)
            else
              params
            end

          params =
            if from_port != via_port do
              params |> Map.put("rport", to_string(from_port))
            else
              params
            end

          {version, protocol, {via_host, via_port}, params}
        end)
    else
      message
    end
    |> Sippet.Transaction.Registry.receive_message()
  end

  def terminate(reason, {socket, address, port}) do
    Logger.info("stopped plug #{:inet.ntoa(address)}:#{port}/udp, " <>
                "reason: #{inspect reason}")
    :ok = :gen_udp.close(socket)
  end

  def terminate(reason, state),
    do: super(reason, state)
end
