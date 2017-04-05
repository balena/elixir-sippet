defmodule Sippet.Transaction do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  defmacro __using__(opts) do
    quote location: :keep do
      use GenStateMachine, callback_mode: [:state_functions, :state_enter]

      alias Sippet.Message, as: Message
      alias Sippet.Message.RequestLine, as: RequestLine

      require Logger

      @tag unquote(opts)[:tag]

      @doc false
      def init(data), do: {:ok, unquote(opts)[:initial_state], data}

      @doc false
      def start_link(
          %Message{start_line: %RequestLine{method: method}} = request,
          opts \\ []) do
        branch = elem(List.last(request.headers.via), 3)["branch"]

        Logger.info("transaction #{branch}/#{@tag}: started")

        :gen_statem.start_link(__MODULE__, %{branch: branch,
                                             request: request}, opts)
      end

      @doc false
      def terminate(reason, _state, %{branch: branch} = data) do
        case reason do
          :normal ->
            Logger.info("transaction #{branch}/#{@tag}: finished gracefuly")
        end
      end

      @doc false
      def shutdown(reason, %{branch: branch} = data) when is_atom(reason) do
        receive_error(reason)

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

      @doc false
      def receive_request(
          %Message{start_line: %RequestLine{}} = incoming_request) do
        core = Application.get_env(:sippet, :core)
        apply(core, :on_request, [incoming_request, self()])
      end

      @doc false
      def receive_response(
          %Message{start_line: %StatusLine{}} = incoming_response) do
        core = Application.get_env(:sippet, :core)
        apply(core, :on_response, [incoming_response, self()])
      end

      @doc false
      def receive_error(reason) when is_atom(reason) do
        core = Application.get_env(:sippet, :core)
        apply(core, :on_error, [reason, self()])
      end

      @doc false
      def send_request(
          %Message{start_line: %RequestLine{}} = outgoing_request) do
        Transport.Registry.send(self(), outgoing_request)
      end

      @doc false
      def send_response(
          %Message{start_line: %StatusLine{}} = outgoing_response) do
        Transport.Registry.send(self(), outgoing_response)
      end

      @doc false
      def reliable?(
          %Message{start_line: %RequestLine{}} = request) do
        Transport.Registry.reliable?(request)
      end
    end
  end

  def on_error(transaction, reason)
      when is_pid(transaction) and is_atom(reason) do
    :gen_statem.cast(transaction, {:error, reason})
  end
end
