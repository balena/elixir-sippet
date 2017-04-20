defmodule Sippet.Transactions.Server do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transactions.Server.State, as: State

  @type request :: %Message{start_line: %RequestLine{}}

  @type response :: %Message{start_line: %StatusLine{}}

  @type reason :: atom | any

  @type branch :: binary

  @type method :: atom | binary

  @type host :: binary

  @type dport :: integer

  @type t :: %__MODULE__{
    branch: branch,
    method: method,
    sent_by: {host, dport}
  }

  @type transaction :: t | GenServer.server

  defstruct [
    branch: nil,
    method: nil,
    sent_by: nil
  ]

  @doc """
  Create a server transaction identifier explicitly.
  """
  @spec new(branch, method, {host, dport}) :: t
  def new(branch, method, sent_by) do
    %__MODULE__{
      branch: branch,
      method: if(method == :ack, do: :invite, else: method),
      sent_by: sent_by
    }
  end

  @doc """
  Create a server transaction identifier from an incoming `request` or an
  outgoing `response`. If they are related, they will be equal.
  """
  @spec new(request | response) :: t
  def new(%Message{start_line: %RequestLine{}} = incoming_request) do
    method = incoming_request.start_line.method

    # Take the topmost via branch
    {_version, _protocol, sent_by, %{"branch" => branch}} =
      hd(incoming_request.headers.via)

    new(branch, method, sent_by)
  end

  def new(%Message{start_line: %StatusLine{}} = outgoing_response) do
    {_sequence, method} = outgoing_response.headers.cseq

    # Take the topmost via sent-by and branch
    {_version, _protocol, sent_by, %{"branch" => branch}} =
      hd(outgoing_response.headers.via)

    new(branch, method, sent_by)
  end

  @doc false
  @spec receive_request(GenServer.server, request) :: :ok
  def receive_request(server, %Message{start_line: %RequestLine{}} = request),
    do: GenStateMachine.cast(server, {:incoming_request, request})

  @doc false
  @spec send_response(GenServer.server, response) :: :ok
  def send_response(server, %Message{start_line: %StatusLine{}} = response),
    do: GenStateMachine.cast(server, {:outgoing_response, response})

  @doc false
  @spec receive_error(GenServer.server, reason) :: :ok
  def receive_error(server, reason),
    do: GenStateMachine.cast(server, {:error, reason})

  defmacro __using__(opts) do
    quote location: :keep do
      use GenStateMachine, callback_mode: [:state_functions, :state_enter]

      alias Sippet.Transactions.Server.State, as: State

      require Logger

      def init(%State{} = data) do
        Logger.info("server transaction #{data.name} started")
        initial_state = unquote(opts)[:initial_state]
        {:ok, initial_state, data}
      end

      defp send_response(response, %State{name: name} = data) do
        extras = data.extras |> Map.put(:last_response, response)
        data = %{data | extras: extras}
        Sippet.Transports.send_message(response, name)
        data
      end

      defp receive_request(request, %State{name: name}),
        do: Sippet.Core.receive_request(request, name)

      def shutdown(reason, %State{name: name} = data) do
        Logger.warn("server transaction #{name} shutdown: #{reason}")
        Sippet.Core.receive_error(reason, name)
        {:stop, :shutdown, data}
      end

      def timeout(data),
        do: shutdown(:timeout, data)

      defdelegate reliable?(request), to: Sippet.Transports

      def unhandled_event(event_type, event_content,
          %State{name: name} = data) do
        Logger.error("server transaction #{name} got " <>
                     "unhandled_event/3: #{inspect event_type}, " <>
                     "#{inspect event_content}, #{inspect data}")
        {:stop, :shutdown, data}
      end
    end
  end
end

defimpl String.Chars, for: Sippet.Transactions.Server do
  def to_string(%Sippet.Transactions.Server{} = transaction) do
    "#{transaction.branch}/#{transaction.method}/" <>
    "#{transaction.sent_by |> elem(0)}:#{transaction.sent_by |> elem(1)}"
  end
end
