defprotocol Sippet.ClientTransaction.User do
  def on_response(user, response)
end

defmodule Sippet.ClientTransaction do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.ClientTransaction.Invite, as: Invite
  alias Sippet.ClientTransaction.NonInvite, as: NonInvite

  def start_link(user, %Message{start_line: %RequestLine{method: method}} = request,
      transport) do
    case method do
      :invite ->
        Invite.start_link(user, request, transport)
      _otherwise ->
        NonInvite.start_link(user, request, transport)
    end
  end

  def on_response(pid, %Message{start_line: %StatusLine{}} = response)
      when is_pid(pid) do
    :gen_statem.cast(pid, {:incoming_response, response})
  end

  def on_error(pid, reason) when is_pid(pid) and is_atom(reason) do
    :gen_statem.cast(pid, {:error, reason})
  end
end

defmodule Sippet.ClientTransaction.Invite do
  use Sippet.Transaction

  alias Sippet.Transport, as: Transport
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.ClientTransaction.User, as: User

  @timer_a 600  # optimization: transaction ends in 37.8s
  @timer_b 64 * @timer_a
  @timer_d 32000  # timer D should be > 32s

  defp retry({past_wait, passed_time},
      %{request: request, transport: transport}) do
    Transport.send(transport, request)
    new_delay = past_wait * 2
    {:keep_state_and_data, [{:state_timeout, new_delay,
       {new_delay, passed_time + new_delay}}]}
  end
  
  defp do_build_ack(_request) do
    #TODO(guibv): build the ACK request using the original request
    :ok
  end

  def init(data), do: {:ok, :calling, data}

  def calling(:enter, _old_state, %{request: request, transport: transport}) do
    Transport.send(transport, request)

    actions =
      if Transport.reliable(transport) do
        [{:state_timeout, @timer_b, {@timer_b, @timer_b}}]
      else
        [{:state_timeout, @timer_a, {@timer_a, @timer_a}}]
      end

    {:keep_state_and_data, actions}
  end

  def calling(:state_timeout, {_past_wait, passed_time} = time_event, data) do
    if passed_time >= @timer_b do
      timeout(data)
    else
      retry(time_event, data)
    end
  end

  def calling(:cast, {:incoming_response, response}, %{user: user} = data) do
    User.on_response(user, response)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:next_state, :proceeding, data}
      2 -> {:stop, :normal, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def calling(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def proceeding(:enter, _old_state, _data),
    do: :keep_state_and_data

  def proceeding(:cast, {:incoming_response, response},
      %{user: user} = data) do
    User.on_response(user, response)
    case StatusLine.status_code_class(response.start_line) do
      1 -> :keep_state_and_data
      2 -> {:stop, :normal, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def proceeding(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def completed(:enter, _old_state,
      %{request: request, transport: transport} = data) do
    ack = do_build_ack(request)
    data = Map.put(data, :ack, ack)
    Transport.send(transport, ack)

    if Transport.reliable(transport) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timer_d, nil}]}
    end
  end

  def completed(:cast, {:incoming_response, response},
      %{ack: ack, transport: transport}) do
    if StatusLine.status_code_class(response.start_line) >= 3 do
      Transport.send(transport, ack)
    end
    :keep_state_and_data
  end

  def completed(:state_timeout, _nil, data),
    do: {:stop, :normal, data}

  def completed(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def handle_event(:cast, {:error, reason}, _state, data),
    do: shutdown(reason, data)

  def handle_event(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)
end

defmodule Sippet.ClientTransaction.NonInvite do
  use Sippet.Transaction

  alias Sippet.Transport, as: Transport
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.ClientTransaction.User, as: User

  @t2 4000
  @timer_e 500
  @timer_f 64 * @timer_e
  @timer_k 5000  # timer K is 5s

  def init(data), do: {:ok, :trying, data}

  defp start_timers(%{transport: transport} = data) do
    data = Map.put(data, :deadline_timer,
        :erlang.start_timer(@timer_f, self(), :deadline))
    
    if Transport.reliable(transport) do
      data
    else
      Map.put(data, :retry_timer,
          :erlang.start_timer(@timer_e, self(), @timer_e))
    end
  end

  defp cancel_timers(data) do
    case data do
      %{deadline_timer: deadline_timer} ->
        :erlang.cancel_timer(deadline_timer)
    end
    case data do
      %{retry_timer: retry_timer} ->
        :erlang.cancel_timer(retry_timer)
    end
    Map.drop(data, [:deadline_timer, :retry_timer])
  end

  defp retry(next_wait, %{request: request, transport: transport} = data) do
    Transport.send(transport, request)
    data = %{data | retry_timer:
        :erlang.start_timer(next_wait, self(), next_wait)}
    {:keep_state, data}
  end

  def trying(:enter, _old_state,
      %{request: request, transport: transport} = data) do
    Transport.send(transport, request)
    data = start_timers(data)
    {:keep_state, data}
  end

  def trying(:info, {:timeout, _timer, :deadline}, data),
    do: timeout(data)

  def trying(:info, {:timeout, _timer, last_delay}, data),
    do: retry(min(last_delay * 2, @t2), data)

  def trying(:cast, {:incoming_response, response}, %{user: user} = data) do
    User.on_response(user, response)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:next_state, :proceeding, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def trying(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def trying(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def proceeding(:enter, _old_state, _data),
    do: :keep_state_and_data

  def proceeding(:info, {:timeout, _timer, :deadline}, data),
    do: timeout(data)

  def proceeding(:info, {:timeout, _timer, _last_delay}, data),
    do: retry(@t2, data)

  def proceeding(:cast, {:incoming_response, response},
      %{user: user} = data) do
    User.on_response(user, response)
    case StatusLine.status_code_class(response.start_line) do
      1 -> :keep_state_and_data
      _ -> {:next_state, :completed, data}
    end
  end

  def proceeding(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def proceeding(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def completed(:enter, _old_state, %{transport: transport} = data) do
    data = cancel_timers(data)
    
    if Transport.reliable(transport) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timer_k, nil}]}
    end
  end

  def completed(:state_timeout, _nil, data),
    do: {:stop, :normal, data}

  def completed(:cast, {:incoming_response, _response}, _data),
    do: :keep_state_and_data

  def completed(:cast, {:error, _reason}, data),
    do: {:stop, :shutdown, data}

  def completed(event_type, event_content, data),
    do: handle_event(event_type, event_content, data)

  def handle_event(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)
end
