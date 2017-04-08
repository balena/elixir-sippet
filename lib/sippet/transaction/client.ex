defmodule Sippet.Transaction.Client do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transaction.Client.State, as: State

  @type request :: %Message{start_line: %RequestLine{}}

  @type response :: %Message{start_line: %StatusLine{}}

  @type reason :: atom | any

  @type branch :: binary

  @type method :: atom | binary

  @type t :: %__MODULE__{
    branch: branch,
    method: method
  }

  @type transaction :: pid | t

  defstruct [
    branch: nil,
    method: nil
  ]

  @doc """
  Create a client transaction identifier explicitly.
  """
  @spec new(branch, method) :: t
  def new(branch, method) do
    %__MODULE__{branch: branch, method: method}
  end

  @doc """
  Create a client transaction identifier from an outgoing `request` or an
  incoming `response`. If they are related, they will be equal.
  """
  @spec new(request | response) :: t
  def new(%Message{start_line: %RequestLine{}} = incoming_request) do
    method = incoming_request.start_line.method

    # Take the topmost via branch
    {_version, _protocol, _sent_by, %{"branch" => branch}} =
      List.first(incoming_request.headers.via)

    new(branch, method)
  end
  def new(%Message{start_line: %StatusLine{}} = outgoing_response) do
    {_sequence, method} = outgoing_response.headers.cseq

    # Take the topmost via branch
    {_version, _protocol, _sent_by, %{"branch" => branch}} =
      List.first(outgoing_response.headers.via)

    new(branch, method)
  end

  @doc false
  @spec receive_response(GenServer.server, response) :: :ok
  def receive_response(server, %Message{start_line: %StatusLine{}} = response),
    do: GenStateMachine.cast(server, {:incoming_response, response})

  @doc false
  @spec receive_error(GenServer.server, reason) :: :ok
  def receive_error(server, reason),
    do: GenStateMachine.cast(server, {:error, reason})

  defmacro __using__(opts) do
    quote location: :keep do
      use GenStateMachine, callback_mode: [:state_functions, :state_enter]

      alias Sippet.Transaction.Client.State, as: State

      require Logger

      def init(%State{} = data) do
        Logger.info("client transaction #{data.name} started")
        initial_state = unquote(opts)[:initial_state]
        {:ok, initial_state, data}
      end

      defp send_request(request, %State{name: name} = data),
        do: Sippet.Transport.send_message(request, name)

      defp receive_response(response, %State{name: name} = data),
        do: Sippet.Core.receive_response(response, name)

      def shutdown(reason, %State{name: name} = data) do
        Logger.warn("client transaction #{name} shutdown: #{reason}")
        Sippet.Core.receive_error(reason, name)
        {:stop, :shutdown, data}
      end

      def timeout(%State{} = data),
        do: shutdown(:timeout, data)

      defdelegate reliable?(request), to: Sippet.Transport

      def unhandled_event(event_type, event_content,
          %State{name: name} = data) do
        Logger.error("client transaction #{name} got " <>
                     "unhandled_event/3: #{inspect event_type}, " <>
                     "#{inspect event_content}, #{inspect data}")
        {:stop, :shutdown, data}
      end
    end
  end
end

defimpl String.Chars, for: Sippet.Transaction.Client do
  def to_string(%Sippet.Transaction.Client{} = transaction),
    do: "#{transaction.branch}/#{transaction.method}"
end
