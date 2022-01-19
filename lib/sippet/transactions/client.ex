defmodule Sippet.Transactions.Client do
  @moduledoc false

  alias Sippet.Message, as: Message
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transactions.Client.State, as: State

  def receive_response(server, %Message{start_line: %StatusLine{}} = response),
    do: GenStateMachine.cast(server, {:incoming_response, response})

  def receive_error(server, reason),
    do: GenStateMachine.cast(server, {:error, reason})

  def terminate(server),
    do: GenStateMachine.cast(server, :terminate)

  defmacro __using__(opts) do
    quote location: :keep do
      use GenStateMachine, callback_mode: [:state_functions, :state_enter]

      alias Sippet.Transactions.Client.State, as: State

      require Logger

      def init(%State{key: key} = data) do
        Logger.debug("client transaction #{inspect(key)} started")

        initial_state = unquote(opts)[:initial_state]
        {:ok, initial_state, data}
      end

      defp send_request(request, %State{key: key, sippet: sippet} = data),
        do: Sippet.Router.send_transport_message(sippet, request, key)

      defp receive_response(response, %State{key: key, sippet: sippet} = data),
        do: Sippet.Router.to_core(sippet, :receive_response, [response, key])

      def shutdown(reason, %State{key: key, sippet: sippet} = data) do
        Logger.warn("client transaction #{inspect(key)} shutdown: #{reason}")

        Sippet.Router.to_core(sippet, :receive_error, [reason, key])

        {:stop, :shutdown, data}
      end

      def timeout(%State{} = data),
        do: shutdown(:timeout, data)

      def reliable?(request, %State{sippet: sippet}),
        do: Sippet.reliable?(sippet, request)

      def unhandled_event(:cast, :terminate, %State{key: key} = data) do
        Logger.debug("client transaction #{inspect(key)} terminated")

        {:stop, :normal, data}
      end

      def unhandled_event(event_type, event_content, %State{key: key} = data) do
        Logger.error([
          "client transaction #{inspect(key)} got unhandled_event/3:",
          " #{inspect(event_type)}, #{inspect(event_content)}, #{inspect(data)}"
        ])

        {:stop, :shutdown, data}
      end

      def child_spec([%{key: client_key}, _] = args) do
        %{
          id: {__MODULE__, client_key},
          start: {__MODULE__, :start_link, [args]},
          restart: :transient
        }
      end

      def start_link([initial_data, opts]),
        do: GenStateMachine.start_link(__MODULE__, initial_data, opts)

      defoverridable init: 1,
                     send_request: 2,
                     receive_response: 2,
                     shutdown: 2,
                     timeout: 1,
                     unhandled_event: 3
    end
  end
end
