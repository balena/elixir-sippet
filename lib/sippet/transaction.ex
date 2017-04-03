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
      alias Sippet.Message.StatusLine, as: StatusLine
      alias Sippet.Transaction.User, as: User

      require Logger

      @doc false
      def start_link(user,
          %Message{start_line: %RequestLine{method: method}} = request,
          transport) do
        branch = elem(List.first(request.headers.via), 3)["branch"]
        :gen_statem.start_link(__MODULE__, %{branch: branch,
                                             user: user,
                                             request: request,
                                             transport: transport}, [])
      end

      @doc false
      def callback_mode(), do: [:state_functions, :state_enter]

      @doc false
      def terminate(reason, _state, %{branch: branch} = data) do
        case reason do
          :normal ->
            Logger.info("transaction #{branch}: finished gracefuly")
          :shutdown ->
            Logger.warn("transaction #{branch}: shutdown")
          {:shutdown, reason} ->
            Logger.warn("transaction #{branch}: shutdown with "
                        <> "#{inspect reason}")
        end
      end

      @doc false
      def code_change(_old, state, _extra) do
        {:ok, state}
      end

      defp shutdown(reason, %{user: user} = data) do
        User.on_error(user, reason)
        {:stop, :shutdown, data}
      end

      def timeout(data), do: shutdown(:timeout, data)

      def unhandled_event(event_type, event_content, data) do
        Logger.error("unhandled event #{inspect event_type}, "
                     <> "#{inspect event_content}")
        {:stop, :shutdown, data}
      end
    end
  end
end
