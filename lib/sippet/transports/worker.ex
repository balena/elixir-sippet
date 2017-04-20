defmodule Sippet.Transports.Worker do
  use GenServer

  alias Sippet.Message, as: Message
  alias Sippet.Transports.Pool, as: Pool
  alias Sippet.Transactions, as: Transactions

  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, nil)

  def init(_) do
    Logger.info("#{inspect self()} message worker ready")
    {:ok, nil}
  end

  def handle_cast({:incoming_datagram, packet, from}, _) do
    case parse_message(packet) do
      {:ok, message} ->
        receive_message(message, from)
      {:error, reason} ->
        {address, port, protocol} = from
        Logger.error("couldn't parse incoming packet from " <>
                     "#{:inet.ntoa(address)}:#{port}/#{protocol}: " <>
                     "#{inspect reason}")
    end

    Pool.check_in(self())
    {:noreply, nil}
  end

  def handle_cast({:validate_message, %Message{} = message, from}, _) do
    validate_message(message, from)

    Pool.check_in(self())
    {:noreply, nil}
  end

  def handle_cast(msg, state), do: super(msg, state)

  defp parse_message(packet) do
    message = String.replace(packet, "\r\n", "\n")
    case String.split(message, "\n\n", parts: 2) do
      [header, body] ->
        parse_message(header <> "\n\n", body)
      [header] ->
        parse_message(header, "")
    end
  end

  defp parse_message(header, body) do
    case Message.parse(header) do
      {:ok, message} -> {:ok, %{message | body: body}}
      other -> other
    end
  end

  defp receive_message(message, {_protocol, ip, from_port} = from) do
    if Message.request?(message) do
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
    |> validate_message(from)
  end

  defp validate_message(message, from) do
    case Message.validate(message, from) do
      :ok ->
        message |> Transactions.receive_message()
      {:error, reason} ->
        Logger.warn("discarded #{message_kind message}, " <>
                    "#{inspect reason}")
    end
  end

  defp message_kind(message),
    do: if(Message.request?(message), do: "request", else: "response")

  def terminate(reason, _) do
    Logger.info("#{inspect self()} stopped message worker, " <>
                "reason #{inspect reason}")
  end
end
