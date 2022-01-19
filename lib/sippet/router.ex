defmodule Sippet.Router do
  @moduledoc false

  alias Sippet.{Message, Transactions, URI}
  alias Sippet.Message.{RequestLine, StatusLine}

  require Logger

  @doc false
  def handle_transport_message(sippet, iodata, from) when is_list(iodata) do
    binary =
      iodata
      |> IO.iodata_to_binary()

    handle_transport_message(sippet, binary, from)
  end

  def handle_transport_message(_sippet, "", _from), do: :ok

  def handle_transport_message(sippet, "\n" <> rest, from),
    do: handle_transport_message(sippet, rest, from)

  def handle_transport_message(sippet, "\r\n" <> rest, from),
    do: handle_transport_message(sippet, rest, from)

  def handle_transport_message(sippet, raw, from) do
    with {:ok, message} <- parse_message(raw),
         prepared_message <- update_via(message, from),
         :ok <- Message.validate(prepared_message, from) do
      receive_transport_message(sippet, prepared_message)
    else
      {:error, reason} ->
        Logger.error(fn ->
          {protocol, address, port} = from

          [
            "discarded message from ",
            "#{ip_to_string(address)}:#{port}/#{protocol}: ",
            "#{inspect(reason)}"
          ]
        end)
    end
  end

  defp parse_message(packet) do
    case String.split(packet, ~r{\r?\n\r?\n}, parts: 2) do
      [header, body] ->
        parse_message(header, body)

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

  defp ip_to_string(ip) when is_binary(ip), do: ip
  defp ip_to_string(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()

  defp update_via(%Message{start_line: %RequestLine{}} = request, {:wss, _ip, _from_port}), do: request

  defp update_via(%Message{start_line: %RequestLine{}} = request, {:ws, _ip, _from_port}), do: request

  defp update_via(%Message{start_line: %RequestLine{}} = request, {_protocol, ip, from_port}) do
    request
    |> Message.update_header_back(:via, fn
      {version, protocol, {via_host, via_port}, params} ->
        host = ip |> ip_to_string()

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
  end

  defp update_via(%Message{start_line: %StatusLine{}} = response, _from), do: response

  @doc false
  def receive_transport_error(sippet, transaction_key, reason) do
    case Registry.lookup(sippet, {:transaction, transaction_key}) do
      [] ->
        Logger.warn(fn ->
          case transaction_key do
            %Transactions.Client.Key{} ->
              "client key #{inspect(transaction_key)} not found"

            %Transactions.Server.Key{} ->
              "server key #{inspect(transaction_key)} not found"
          end
        end)

      [{pid, _}] ->
        # Send the response through the existing server key.
        case transaction_key do
          %Transactions.Client.Key{} ->
            Transactions.Client.receive_error(pid, reason)

          %Transactions.Server.Key{} ->
            Transactions.Server.receive_error(pid, reason)
        end
    end

    :ok
  end

  @doc false
  def send_transport_message(sippet, message, key) do
    {protocol, host, port} = get_destination(message)

    GenServer.call(
      {:via, Registry, {sippet, {:transport, protocol}}},
      {:send_message, message, host, port, key}
    )
  end

  @doc false
  def to_core(sippet, fun, args) do
    case Registry.meta(sippet, :core) do
      :error ->
        raise RuntimeError, "Core not initialized"

      {:ok, module} ->
        apply(module, fun, args)
    end
  end

  @doc false
  def send_transaction_request(sippet, %Message{start_line: %RequestLine{}} = outgoing_request) do
    transaction = Transactions.Client.Key.new(outgoing_request)

    # Create a new client transaction now. The request is passed to the
    # transport once it starts.
    case start_client(sippet, transaction, outgoing_request) do
      {:ok, _} ->
        :ok

      {:ok, _, _} ->
        :ok

      _errors ->
        Logger.warn(fn ->
          "client transaction #{transaction} already exists"
        end)

        {:error, :already_started}
    end
  end

  @doc false
  def send_transaction_response(sippet, %Message{start_line: %StatusLine{}} = outgoing_response) do
    server_key = Transactions.Server.Key.new(outgoing_response)

    case Registry.lookup(sippet, {:transaction, server_key}) do
      [] ->
        {:error, :no_transaction}

      [{pid, _}] ->
        # Send the response through the existing server transaction.
        Transactions.Server.send_response(pid, outgoing_response)
    end
  end

  @doc false
  defp receive_transport_message(sippet, %Message{start_line: %RequestLine{}} = incoming_request) do
    transaction = Transactions.Server.Key.new(incoming_request)

    case Registry.lookup(sippet, {:transaction, transaction}) do
      [] ->
        if incoming_request.start_line.method == :ack do
          # Redirect to the core directly. ACKs sent out of transactions
          # pertain to the core.
          to_core(sippet, :receive_request, [incoming_request, nil])
        else
          # Start a new server transaction now. The transaction will redirect
          # to the core once it starts. It will return errors only if there was
          # some kind of race condition when receiving the request.
          start_server(sippet, transaction, incoming_request)
        end

      [{pid, _}] ->
        # Redirect the request to the existing transaction. These are tipically
        # retransmissions or ACKs for 200 OK responses.
        Transactions.Server.receive_request(pid, incoming_request)
    end
  end

  @doc false
  defp receive_transport_message(sippet, %Message{start_line: %StatusLine{}} = incoming_response) do
    transaction = Transactions.Client.Key.new(incoming_response)

    case Registry.lookup(sippet, {:transaction, transaction}) do
      [] ->
        # Redirect the response to core. These are tipically retransmissions of
        # 200 OK for sent INVITE requests, and they have to be handled directly
        # by the core in order to catch the correct media handling.
        to_core(sippet, :receive_response, [incoming_response, nil])

      [{pid, _}] ->
        # Redirect the response to the existing client transaction. If needed,
        # the client transaction will redirect to the core from there.
        Transactions.Client.receive_response(pid, incoming_response)
    end
  end

  defp start_client(
         sippet,
         %Transactions.Client.Key{} = key,
         %Message{start_line: %RequestLine{}} = outgoing_request
       ) do
    module =
      case key.method do
        :invite -> Transactions.Client.Invite
        _otherwise -> Transactions.Client.NonInvite
      end

    initial_data = Transactions.Client.State.new(outgoing_request, key, sippet)

    DynamicSupervisor.start_child(
      :"#{sippet}_sup",
      {module, [initial_data, [name: {:via, Registry, {sippet, {:transaction, key}}}]]}
    )
  end

  defp start_server(
         sippet,
         %Transactions.Server.Key{} = key,
         %Message{start_line: %RequestLine{}} = incoming_request
       ) do
    module =
      case key.method do
        :invite -> Transactions.Server.Invite
        _otherwise -> Transactions.Server.NonInvite
      end

    initial_data = Transactions.Server.State.new(incoming_request, key, sippet)

    DynamicSupervisor.start_child(
      :"#{sippet}_sup",
      {module, [initial_data, [name: {:via, Registry, {sippet, {:transaction, key}}}]]}
    )
  end

  defp get_destination(%Message{target: target}) when is_tuple(target),
    do: target

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
            %{"rport" => rport} -> rport |> String.to_integer()
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
end
