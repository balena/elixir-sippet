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

  use Supervisor

  import Kernel, except: [send: 2]

  alias Sippet.{Message, Transactions}
  alias Sippet.Message.{RequestLine, StatusLine}

  require Logger

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

  @typedoc "Sippet identifier"
  @type sippet :: atom

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
  @spec send(sippet, request | response) :: :ok | {:error, reason}
  def send(sippet, message) when is_atom(sippet) do
    unless Message.valid?(message) do
      raise ArgumentError, "expected :message argument to be a valid SIP message"
    end

    do_send(sippet, message)
  end

  defp do_send(sippet, %Message{start_line: %RequestLine{method: :ack}} = request),
    do: Sippet.Router.send_transport_message(sippet, request, nil)

  defp do_send(sippet, %Message{start_line: %RequestLine{}} = outgoing_request),
    do: Sippet.Router.send_transaction_request(sippet, outgoing_request)

  defp do_send(sippet, %Message{start_line: %StatusLine{}} = outgoing_response),
    do: Sippet.Router.send_transaction_response(sippet, outgoing_response)

  @doc """
  Verifies if the transport protocol used to send the given message is
  reliable.
  """
  @spec reliable?(sippet, Message.t()) :: boolean
  def reliable?(sippet, %Message{headers: %{via: [via | _]}})
      when is_atom(sippet) do
    {_version, protocol, _host_and_port, _params} = via

    case Registry.lookup(sippet, {:transport, protocol}) do
      [{_, reliable}] ->
        reliable

      _ ->
        raise ArgumentError, message: "protocol not registered"
    end
  end

  @doc """
  Registers a transport for a given protocol.
  """
  @spec register_transport(sippet, atom, boolean) :: :ok | {:error, :already_registered}
  def register_transport(sippet, protocol, reliable)
      when is_atom(sippet) and is_atom(protocol) and is_boolean(reliable) do
    case Registry.register(sippet, {:transport, protocol}, reliable) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, _}} ->
        {:error, :already_registered}
    end
  end

  @doc """
  Registers the stack core.
  """
  @spec register_core(sippet, atom) :: :ok
  def register_core(sippet, module)
      when is_atom(sippet) and is_atom(module) do
    Registry.put_meta(sippet, :core, module)
  end

  @doc """
  Terminates a client or server transaction forcefully.

  This function is not generally executed by entities; there is a single case
  where it is fundamental, which is when a client transaction is in proceeding
  state for a long time, and the transaction has to be finished forcibly, or it
  will never finish by itself.

  If a transaction with such a key does not exist, it will be silently ignored.
  """
  @spec terminate(sippet, client_key | server_key) :: :ok
  def terminate(sippet, key) do
    case Registry.lookup(sippet, {:transaction, key}) do
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
  def start_link(options) when is_list(options) do
    name =
      case Keyword.fetch(options, :name) do
        {:ok, name} when is_atom(name) ->
          name

        {:ok, other} ->
          raise ArgumentError, "expected :name to be an atom, got: #{inspect(other)}"

        :error ->
          raise ArgumentError, "expected :name option to be present"
      end

    Supervisor.start_link(__MODULE__, options, name: :"#{name}_sup")
  end

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @impl true
  def init(options) do
    children = [
      {Registry, [name: options[:name], keys: :unique, partitions: System.schedulers_online()]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
