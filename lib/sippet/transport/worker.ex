defmodule Sippet.Transport.Worker do
  use GenServer

  alias Sippet.Message, as: Message

  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, nil)

  def init(_) do
    Logger.info("#{inspect self()} worker ready")
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
    if message |> has_required_headers() and
       message |> has_valid_via(from) and
       message |> has_valid_body() and
       message |> has_tag_on(:from) do
      if Message.request?(message) do
        if validate_request(message) do
          message |> Sippet.Transaction.receive_message()
        end
      else
        if validate_response(message) do
          message |> Sippet.Transaction.receive_message()
        end
      end
    end
  end

  defp has_required_headers(message) do
    required = [:to, :from, :cseq, :call_id, :max_forwards, :via]
    missing_headers =
      for header <- required, not message |> Message.has_header?(header) do
        header
      end
    if Enum.empty?(missing_headers) do
      true
    else
      Logger.warn("discarded #{message_kind message}, " <>
          "missing headers: #{inspect missing_headers}")
      false
    end
  end

  defp message_kind(message),
    do: if(Message.request?(message), do: "request", else: "response")

  defp has_valid_via(message, {protocol1, _ip, _port}) do
    {_version, protocol2, _sent_by, _params} = hd(message.headers.via)
    if protocol1 != protocol2 do
      Logger.warn("discarded #{message_kind message}, " <>
                  "Via protocol doesn't match transport protocol")
      false
    else
      has_valid_via(message, message.headers.via)
    end
  end

  defp has_valid_via(_, []), do: true
  defp has_valid_via(message, [via|rest]) do
    {version, _protocol, _sent_by, params} = via
    if version != {2, 0} do
      Logger.warn("discarded #{message_kind message}, " <>
                  "Via version #{inspect version} is unknown")
      false
    else
      case params do
        %{"branch" => branch} ->
          if branch |> String.starts_with?("z9hG4bK") do
            has_valid_via(message, rest)
          else
            Logger.warn("discarded #{message_kind message}, " <>
                        "Via branch doesn't start with the magic cookie")
            false
          end
        _otherwise ->
          Logger.warn("discarded #{message_kind message}, " <>
                      "Via header doesn't have branch parameter")
          false
      end
    end
  end

  defp has_valid_body(message) do
    case message.headers do
      %{content_length: content_length} ->
        message.body != nil and length(message.body) == content_length
      _otherwise ->
        message.body == nil
    end
  end

  defp has_tag_on(message, header) do
    {_display_name, _uri, params} = message.headers[header]
    case params do
      %{"tag" => value} ->
        if length(value) > 0 do
          true
        else
          Logger.warn("discarded #{message_kind message}, " <>
                      "empty #{inspect header} tag")
          false
        end
      _otherwise ->
        Logger.warn("discarded #{message_kind message}, " <>
                    "#{inspect header} tag does not exist")
        false
    end
  end

  defp validate_request(request) do
    request |> has_matching_cseq()
  end

  defp has_matching_cseq(request) do
    method1 = request.start_line.method
    {_sequence, method2} = request.headers.cseq
    if method1 == method2 do
      true
    else
      Logger.warn("discarded request, invalid CSeq method")
      false
    end
  end

  defp validate_response(response) do
    response |> has_valid_status_line_version()
  end

  defp has_valid_status_line_version(response) do
    %{version: version} = response
    if version == {2, 0} do
      true
    else
      Logger.warn("discarded response, invalid status line version " <>
                  "#{inspect version}")
      false
    end
  end
end
