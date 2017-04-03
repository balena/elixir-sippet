defprotocol Sippet.Transaction.User do
  @doc """
  Sends receives an error from the transaction.
  """
  def on_error(user, reason)
end

defmodule Sippet.Transaction do
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

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Sippet.Transaction

      alias Sippet.Message, as: Message
      alias Sippet.Message.RequestLine, as: RequestLine
      alias Sippet.Transaction.User, as: User

      require Logger

      @doc false
      def start_link(client_or_server, user, request, transport) do
        start_link(user, request, transport, [])
      end

      @doc false
      def start_link(client_or_server, user,
          %Message{start_line: %RequestLine{method: method}} = request,
          transport, opts) do
        branch = elem(List.first(request.headers.via), 3)["branch"]

        Logger.info("transaction #{branch}/#{client_or_server}: started")

        :gen_statem.start_link(__MODULE__, %{type: client_or_server,
                                             branch: branch,
                                             user: user,
                                             request: request,
                                             transport: transport}, opts)
      end

      @doc false
      def callback_mode(), do: [:state_functions, :state_enter]

      @doc false
      def terminate(reason, _state, %{type: type, branch: branch} = data) do
        case reason do
          :normal ->
            Logger.info("transaction #{branch}/#{type}: finished gracefuly")
        end
      end

      @doc false
      def code_change(_old_vsn, old_state, old_data, _extra) do
        {:ok, old_state, old_data}
      end

      @doc false
      def shutdown(reason, %{type: type, branch: branch, user: user} = data) do
        User.on_error(user, reason)

        Logger.warn("transaction #{branch}/#{type}: shutdown with "
                    <> "#{inspect reason}")

        {:stop, :shutdown, data}
      end

      @doc false
      def timeout(data), do: shutdown(:timeout, data)

      @doc false
      def unhandled_event(event_type, event_content,
          %{type: type, branch: branch} = data) do
        Logger.error("transaction #{branch}/#{type}: " <>
                     "unhandled event #{inspect event_type}, " <>
                     "#{inspect event_content}")

        {:stop, :shutdown, data}
      end
    end
  end
end
