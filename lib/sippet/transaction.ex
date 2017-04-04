defmodule Sippet.Transaction do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  @type data :: term
  @type state :: atom
  @type event_timeout :: integer
  @type state_timeout :: integer
  @type from :: {to :: pid, tag :: term}

  @type event_type ::
    {:call, from} |
    :cast |
    :info |
    :timeout |
    :state_timeout |
    :internal

  @type reply_action ::
    {:reply, from, reply :: term}

  @type enter_action ::
    :hibernate |
    {:hibernate, boolean} |
    event_timeout |
    {:timeout, event_timeout, event_content :: term} |
    {:state_timeout, state_timeout, event_content :: term} |
    reply_action

  @type action ::
    :postpone |
    {:postpone, boolean} |
    {:next_event, event_type, event_content :: term} |
    enter_action

  @callback init(data) ::
    {:ok, state, data} |
    {:ok, state, data, action | [action]} |
    :ignore |
    {:stop, reason :: term}

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Sippet.Transaction

      alias Sippet.Message, as: Message
      alias Sippet.Message.RequestLine, as: RequestLine

      require Logger

      @tag unquote(opts)[:tag]

      @doc false
      def start_link(request) do
        start_link(request, [])
      end

      @doc false
      def start_link(
          %Message{start_line: %RequestLine{method: method}} = request,
          opts) do
        branch = elem(List.last(request.headers.via), 3)["branch"]

        Logger.info("transaction #{branch}/#{@tag}: started")

        core = Application.get_env(:sippet, :core)
        :gen_statem.start_link(__MODULE__, %{core: core,
                                             branch: branch,
                                             request: request}, opts)
      end

      @doc false
      def callback_mode(), do: [:state_functions, :state_enter]

      @doc false
      def terminate(reason, _state, %{branch: branch} = data) do
        case reason do
          :normal ->
            Logger.info("transaction #{branch}/#{@tag}: finished gracefuly")
        end
      end

      @doc false
      def code_change(_old_vsn, old_state, old_data, _extra) do
        {:ok, old_state, old_data}
      end

      @doc false
      def shutdown(reason, %{branch: branch} = data) do
        Sippet.Transaction.error_to_core(data, reason)

        Logger.warn("transaction #{branch}/#{@tag}: shutdown with "
                    <> "#{inspect reason}")

        {:stop, :shutdown, data}
      end

      @doc false
      def timeout(data), do: shutdown(:timeout, data)

      @doc false
      def unhandled_event(event_type, event_content,
          %{branch: branch} = data) do
        Logger.error("transaction #{branch}/#{@tag}: " <>
                     "unhandled event #{inspect event_type}, " <>
                     "#{inspect event_content}")

        {:stop, :shutdown, data}
      end
    end
  end

  def on_error(transaction, reason)
      when is_pid(transaction) and is_atom(reason) do
    :gen_statem.cast(transaction, {:error, reason})
  end

  def request_to_core(%{core: core},
      %Message{start_line: %RequestLine{}} = incoming_request),
    do: apply(core, :on_request, [incoming_request, self()])

  def response_to_core(%{core: core},
      %Message{start_line: %StatusLine{}} = incoming_response),
    do: apply(core, :on_response, [incoming_response, self()])

  def error_to_core(%{core: core}, reason) when is_atom(reason),
    do: apply(core, :on_error, [reason, self()])
end
