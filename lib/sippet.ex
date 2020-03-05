defmodule Sippet do
  @moduledoc """
  Holds the Sippet stack.

  Network transport protocols should be registered during initialization:

      def init(_) do
        Sippet.register_transport(:udp, false)
        ...
      end

  Messages are dispatched to transports by sending the following message:

      send(pid, {:send_message, message, host, port, transaction})

  Whenever a message is received by a transport, the function
  `Sippet.handle_transport_message` is called, which will validate and route
  messages through the transaction layer or send directly to the core.
  """

  use GenServer

  import Kernel, except: [send: 2]

  alias Sippet.{Message, Transactions, URI}
  alias Sippet.Message.{RequestLine, StatusLine}

  require Logger

  defstruct supervisor: nil,
            core: nil

  @typedoc "A SIP message request"
  @type request :: Message.request()

  @typedoc "A SIP message response"
  @type response :: Message.response()

  @typedoc "An network error that occurred while sending a message"
  @type reason :: term

  @typedoc "A client transaction identifier"
  @type client_key :: Transactions.Client.Key.t()

  @typedoc "A server transaction identifier"
  @type server_key :: Transactions.Server.Key.t()

  @doc """
  Handles the sigil `~K`.

  It returns a client or server transaction key depending on the number of
  parameters passed.

  ## Examples

      iex> import Sippet, only: [sigil_K: 2]

      iex> Sippet.Transactions.Client.Key.new("z9hG4bK230f2.1", :invite)
      ~K[z9hG4bK230f2.1|:invite]

      iex> ~K[z9hG4bK230f2.1|INVITE]
      ~K[z9hG4bK230f2.1|:invite]

      iex> Sippet.Transactions.Server.Key.new("z9hG4bK74b21", :invite, {"client.biloxi.example.com", 5060})
      ~K[z9hG4bK74b21|:invite|client.biloxi.example.com:5060]

      iex> ~K[z9hG4bK74b21|INVITE|client.biloxi.example.com:5060]
      ~K[z9hG4bK74b21|:invite|client.biloxi.example.com:5060]

  """
  def sigil_K(string, _) do
    case String.split(string, "|") do
      [branch, method] ->
        Transactions.Client.Key.new(branch, sigil_to_method(method))

      [branch, method, sentby] ->
        [host, port] = String.split(sentby, ":")

        Transactions.Server.Key.new(
          branch,
          sigil_to_method(method),
          {host, String.to_integer(port)}
        )
    end
  end

  defp sigil_to_method(method) do
    case method do
      ":" <> rest -> Message.to_method(rest)
      other -> Message.to_method(other)
    end
  end

  @doc """
  Sends a message (request or response) using transactions if possible.

  Requests of method `:ack` is sent directly to the transport layer.

  A `Sippet.Transactions.Client` is created for requests to handle client
  retransmissions, when the transport presumes it, and match response
  retransmissions, so the `Sippet.Core` doesn't get retransmissions other than
  200 OK for `:invite` requests.

  In case of success, returns `:ok`.
  """
  @spec send(GenServer.server(), request | response) :: :ok | {:error, reason}
  def send(sippet, %Message{start_line: %RequestLine{method: :ack}} = request) do
    GenServer.call(sippet, {:send_transport_message, request})
  end

  def send(sippet, %Message{start_line: %RequestLine{}} = outgoing_request) do
    GenServer.call(sippet, {:send_transaction_request, outgoing_request})
  end

  def send(sippet, %Message{start_line: %StatusLine{}} = outgoing_response) do
    GenServer.call(sippet, {:send_transaction_response, outgoing_response})
  end

  @doc """
  Verifies if the transport protocol used to send the given message is
  reliable.
  """
  @spec reliable?(Message.t()) :: boolean
  def reliable?(%Message{headers: %{via: via}}) do
    {_version, protocol, _host_and_port, _params} = hd(via)

    case Registry.lookup(Sippet.Registry, {:transport, protocol}) do
      [{_, reliable}] ->
        reliable

      _ ->
        raise ArgumentError, message: "protocol not registered"
    end
  end

  @doc """
  Registers a transport for a given protocol.
  """
  @spec register_transport(atom, boolean) :: :ok | {:error, :already_registered}
  def register_transport(protocol, reliable)
      when is_atom(protocol) and is_boolean(reliable) do
    case Registry.register(Sippet.Registry, {:transport, protocol}, reliable) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, _}} ->
        {:error, :already_registered}
    end
  end

  @doc """
  Terminates a client or server transaction forcefully.

  This function is not generally executed by entities; there is a single case
  where it is fundamental, which is when a client transaction is in proceeding
  state for a long time, and the transaction has to be finished forcibly, or it
  will never finish by itself.

  If a transaction with such a key does not exist, it will be silently ignored.
  """
  @spec terminate(client_key | server_key) :: :ok
  def terminate(key) do
    case Registry.lookup(Sippet.Registry, {:transaction, key}) do
      [] ->
        :ok

      [{pid, _}] ->
        # Send the response through the existing server key.
        case key do
          %Transactions.Client.Key{} ->
            Transactions.Client.terminate(pid)

          %Transactions.Server.Key{} ->
            Transactions.Server.terminate(pid)
        end
    end
  end

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
      GenServer.call(sippet, {:receive_transport_message, prepared_message})
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
  def start_link(init_args) do
    if not Keyword.has_key?(init_args, :core) do
      raise ArgumentError, message: "missing core"
    end

    GenServer.start_link(__MODULE__, init_args)
  end

  @impl true
  def init(args) do
    {:ok, sup_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)

    {:ok, %__MODULE__{supervisor: sup_pid, core: args[:core]}}
  end

  @impl true
  def handle_info(
        {:receive_transport_error, transaction_key, reason},
        state
      ) do
    case Registry.lookup(Sippet.Registry, {:transaction, transaction_key}) do
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

    {:noreply, state}
  end

  def handle_info(
        {:send_transport_message, message, key},
        state
      ) do
    {protocol, host, port} = get_destination(message)

    case Registry.lookup(Sippet.Registry, {:transport, protocol}) do
      [{pid, _}] ->
        Kernel.send(pid, {:send_message, message, host, port, key})

      _ ->
        Logger.error("protocol #{inspect(protocol)} not registered")
    end

    {:noreply, state}
  end

  def handle_info(
        {:to_core, fun, args},
        %{core: core} = state
      ) do
    apply(core, fun, args)

    {:noreply, state}
  end

  @impl true
  def handle_call(
        {:send_transaction_request, %Message{start_line: %RequestLine{}} = outgoing_request},
        _from,
        state
      ) do
    transaction = Transactions.Client.Key.new(outgoing_request)

    # Create a new client transaction now. The request is passed to the
    # transport once it starts.
    result =
      case start_client(transaction, outgoing_request, state) do
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

    {:reply, result, state}
  end

  def handle_call(
        {:send_transaction_response, %Message{start_line: %StatusLine{}} = outgoing_response},
        _from,
        state
      ) do
    server_key = Transactions.Server.Key.new(outgoing_response)

    result =
      case Registry.lookup(Sippet.Registry, {:transaction, server_key}) do
        [] ->
          {:error, :no_transaction}

        [{pid, _}] ->
          # Send the response through the existing server transaction.
          Transactions.Server.send_response(pid, outgoing_response)
      end

    {:reply, result, state}
  end

  def handle_call(
        {:receive_transport_message, %Message{start_line: %RequestLine{}} = incoming_request},
        _from,
        %{core: core} = state
      ) do
    transaction = Transactions.Server.Key.new(incoming_request)

    case Registry.lookup(Sippet.Registry, {:transaction, transaction}) do
      [] ->
        if incoming_request.start_line.method == :ack do
          # Redirect to the core directly. ACKs sent out of transactions
          # pertain to the core.
          apply(core, :receive_request, [incoming_request, nil])
        else
          # Start a new server transaction now. The transaction will redirect
          # to the core once it starts. It will return errors only if there was
          # some kind of race condition when receiving the request.
          start_server(transaction, incoming_request, state)
        end

      [{pid, _}] ->
        # Redirect the request to the existing transaction. These are tipically
        # retransmissions or ACKs for 200 OK responses.
        Transactions.Server.receive_request(pid, incoming_request)
    end

    {:reply, :ok, state}
  end

  def handle_call(
         {:receive_transport_message, %Message{start_line: %StatusLine{}} = incoming_response},
         _from,
         %{core: core} = state
       ) do
    transaction = Transactions.Client.Key.new(incoming_response)

    case Registry.lookup(Sippet.Registry, {:transaction, transaction}) do
      [] ->
        # Redirect the response to core. These are tipically retransmissions of
        # 200 OK for sent INVITE requests, and they have to be handled directly
        # by the core in order to catch the correct media handling.
        apply(core, :receive_response, [incoming_response, nil])

      [{pid, _}] ->
        # Redirect the response to the existing client transaction. If needed,
        # the client transaction will redirect to the core from there.
        Transactions.Client.receive_response(pid, incoming_response)
    end

    {:reply, :ok, state}
  end

  defp start_client(
         %Transactions.Client.Key{} = key,
         %Message{start_line: %RequestLine{}} = outgoing_request,
         %{supervisor: sup}
       ) do
    module =
      case key.method do
        :invite -> Transactions.Client.Invite
        _otherwise -> Transactions.Client.NonInvite
      end

    initial_data = Transactions.Client.State.new(outgoing_request, key, self())

    Supervisor.start_child(sup, {module, [initial_data, [name: via_tuple(key)]]})
  end

  defp start_server(
         %Transactions.Server.Key{} = key,
         %Message{start_line: %RequestLine{}} = incoming_request,
         %{supervisor: sup}
       ) do
    module =
      case key.method do
        :invite -> Transactions.Server.Invite
        _otherwise -> Transactions.Server.NonInvite
      end

    initial_data = Transactions.Server.State.new(incoming_request, key, self())

    Supervisor.start_child(sup, {module, [initial_data, [name: via_tuple(key)]]})
  end

  defp via_tuple(%Transactions.Client.Key{} = client_key),
    do: do_via_tuple(client_key)

  defp via_tuple(%Transactions.Server.Key{} = server_key),
    do: do_via_tuple(server_key)

  defp do_via_tuple(key), do: {:via, Registry, {__MODULE__, key}}

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
