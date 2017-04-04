defmodule Sippet.ServerTransaction do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.ServerTransaction.Invite, as: Invite
  alias Sippet.ServerTransaction.NonInvite, as: NonInvite

  def get_module(%Message{start_line: %RequestLine{method: method}}) do
    case method do
      :invite -> Invite
      _otherwise -> NonInvite
    end
  end

  def send_response(transaction,
      %Message{start_line: %StatusLine{}} = response)
      when is_pid(transaction) do
    :gen_statem.cast(transaction, {:send_response, response})
  end

  def on_request(transaction, %Message{start_line: %RequestLine{}} = request)
      when is_pid(transaction) do
    :gen_statem.cast(transaction, {:incoming_request, request})
  end
end

defmodule Sippet.ServerTransaction.Invite do
  use Sippet.Transaction, tag: 'invite/server'

  alias Sippet.Transport, as: Transport
  alias Sippet.Message.StatusLine, as: StatusLine

  @t2 4000
  @before_trying 200
  @max_idle @t2 - @before_trying
  @timer_g 500
  @timer_h 64 * @timer_g
  @timer_i 5000  # timer I is 5s

  defp retry({past_wait, passed_time}, %{last_response: last_response}) do
    Transport.Registry.send(last_response)
    new_delay = min(past_wait * 2, @t2)
    {:keep_state_and_data, [{:state_timeout, new_delay,
       {new_delay, passed_time + new_delay}}]}
  end

  def init(data), do: {:ok, :proceeding, data}

  def proceeding(:enter, _old_state, %{request: request} = data) do
    Sippet.Transaction.request_to_core(data, request)
    {:keep_state_and_data, [{:state_timeout, @before_trying, :still_trying}]}
  end

  def proceeding(:state_timeout, :still_trying, %{request: request} = data) do
    response = request |> Message.build_response(100)
    Transport.Registry.send(response)
    data = %{data | last_response: response}
    {:keep_state, data, [{:state_timeout, @max_idle, :idle}]}
  end

  def proceeding(:state_timeout, :idle, data),
    do: shutdown(:idle, data)

  def proceeding(:cast, {:incoming_request, _request},
      %{last_response: last_response}) do
    Transport.Registry.send(last_response)
    :keep_state_and_data
  end

  def proceeding(:cast, {:incoming_request, _request}, _data),
    do: :keep_state_and_data

  def proceeding(:cast, {:send_response, response}, data) do
    Transport.Registry.send(response)
    data = Map.put(data, :last_response, response)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:keep_state, data}
      2 -> {:stop, :normal, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def proceeding(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def proceeding(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def completed(:enter, _old_state, %{request: request}) do
    actions =
      if Transport.Registry.reliable(request) do
        [{:state_timeout, @timer_h, {@timer_h, @timer_h}}]
      else
        [{:state_timeout, @timer_g, {@timer_g, @timer_g}}]
      end

    {:keep_state_and_data, actions}
  end

  def completed(:state_timeout, {_past_wait, passed_time} = time_event, data) do
    if passed_time >= @timer_h do
      timeout(data)
    else
      retry(time_event, data)
    end
  end

  def completed(:cast, {:incoming_request, request},
      %{last_response: last_response} = data) do
    case request.start_line.method do
      :invite ->
        Transport.Registry.send(last_response)
        :keep_state_and_data
      :ack -> {:next_state, :confirmed, data}
      _otherwise -> shutdown(:invalid_method, data)
    end
  end

  def completed(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def completed(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def confirmed(:enter, _old_state, %{request: request} = data) do
    if Transport.Registry.reliable(request) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timer_i, nil}]}
    end
  end

  def confirmed(:state_timeout, _nil, data),
    do: {:stop, :normal, data}

  def confirmed(:cast, {:incoming_request, _request}, _data),
    do: :keep_state_and_data

  def confirmed(:cast, {:error, _reason}, data),
    do: {:stop, :shutdown, data}

  def confirmed(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def handle_event(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)
end

defmodule Sippet.ServerTransaction.NonInvite do
  use Sippet.Transaction, tag: 'non-invite/server'

  alias Sippet.Transport, as: Transport
  alias Sippet.Message.StatusLine, as: StatusLine

  @max_idle 4000
  @timer_j 32000

  def init(data), do: {:ok, :trying, data}

  def trying(:enter, _old_state, %{request: request} = data) do
    Sippet.Transaction.request_to_core(data, request)
    {:keep_state_and_data, [{:state_timeout, @max_idle, nil}]}
  end

  def trying(:state_timeout, _nil, data),
    do: shutdown(:idle, data)

  def trying(:cast, {:incoming_request, _request}, _data),
    do: :keep_state_and_data

  def trying(:cast, {:send_response, response}, data) do
    Transport.Registry.send(response)
    data = Map.put(data, :last_response, response)
    case StatusLine.status_code_class(response) do
      1 -> {:next_state, :proceeding, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def trying(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def proceeding(:enter, _old_state, _data),
    do: :keep_state_and_data

  def proceeding(:cast, {:incoming_request, _request},
      %{last_response: last_response}) do
    Transport.Registry.send(last_response)
    :keep_state_and_data
  end

  def proceeding(:cast, {:send_response, response}, data) do
    Transport.Registry.send(response)
    data = Map.put(data, :last_response, response)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:keep_state, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def proceeding(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def completed(:enter, _old_state, %{request: request} = data) do
    if Transport.Registry.reliable(request) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timer_j, nil}]}
    end
  end

  def completed(:state_timeout, _nil, data),
    do: {:stop, :normal, data}

  def completed(:cast, {:incoming_request, _request},
      %{last_response: last_response}) do
    Transport.Registry.send(last_response)
    :keep_state_and_data
  end

  def completed(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def handle_event(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def handle_event(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)
end
