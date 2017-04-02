defprotocol Sippet.ServerTransaction.User do
  def on_request(user, request)
  def on_error(user, reason)
end

defmodule Sippet.ServerTransaction do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  def start_link(user, %Message{start_line: %RequestLine{method: method}} = request,
      transport) do
    case method do
      :invite ->
        Invite.start_link(user, request, transport)
      _otherwise ->
        NonInvite.start_link(user, request, transport)
    end
  end

  def send_response(pid, %Message{start_line: %StatusLine{}} = response)
      when is_pid(pid) do
    :gen_statem.cast(pid, {:send_response, response})
  end

  def on_request(pid, %Message{start_line: %RequestLine{}} = request)
      when is_pid(pid) do
    :gen_statem.cast(pid, {:incoming_request, request})
  end

  def on_error(pid, reason) when is_pid(pid) and is_atom(reason) do
    :gen_statem.cast(pid, {:error, reason})
  end
end

defmodule Sippet.ServerTransaction.Invite do
  alias Sippet.Transport, as: Transport

  @t2 4000
  @timerG 500
  @timerH 64 * @timerG
  @timerI 5000  # timer I is 5s

  def start_link(user, request, transport) do
    :gen_statem.start_link(__MODULE__, %{user: user,
                                         request: request,
                                         transport: transport}, [])
  end

  def callback_mode(), do: [:state_functions, :state_enter]

  defp retry({past_wait, passed_time},
      %{last_response: last_response, transport: transport}) do
    Transport.send(transport, last_response)
    new_delay = min(past_wait * 2, @t2)
    {:keep_state_and_data, [{:state_timeout, new_delay,
       {new_delay, passed_time + new_delay}}]}
  end

  defp shutdown(reason, %{user: user} = data) do
    User.on_error(user, reason)
    {:stop, :shutdown, data}
  end

  defp timeout(data), do: shutdown(:timeout, data)

  def init(data), do: {:ok, :calling, data}

  def proceeding(:enter, _old_state, %{user: user, request: request}) do
    User.on_request(user, request)
    {:keep_state_and_data, [{:state_timeout, 200, nil}]}
  end

  def proceeding(:state_timeout, _nil, _data) do
    # TODO(guibv): create a 100 Trying response and send it
    :keep_state_and_data
  end

  def proceeding(:cast, {:incoming_request, _request},
      %{last_response: last_response, transport: transport}) do
    Transport.send(transport, last_response)
    :keep_state_and_data
  end

  def proceeding(:cast, {:incoming_request, _request}, _data),
    do: :keep_state_and_data

  def proceeding(:cast, {:send_response, response},
      %{transport: transport} = data) do
    Transport.send(transport, response)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:keep_state, Map.put(data, :last_response, response)}
      2 -> {:stop, :normal, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def proceeding(:cast, {:error, reason}, data), do: shutdown(reason, data)

  def completed(:enter, _old_state, %{transport: transport}) do
    actions = if Transport.reliable(transport) do
        [{:state_timeout, @timerH, {@timerH, @timerH}}]  # start timer H
      else
        [{:state_timeout, @timerG, {@timerG, @timerG}}]  # start timer G
      end
    {:keep_state_and_data, actions}
  end

  def completed(:state_timeout, {_past_wait, passed_time} = time_event, data) do
    if passed_time >= @timerH do
      timeout(data)
    else
      retry(time_event, data)
    end
  end

  def completed(:cast, {:incoming_request, request},
      %{last_response: last_response, transport: transport} = data) do
    case request.start_line.method do
      :invite ->
        Transport.send(transport, last_response)
        :keep_state_and_data
      :ack ->
        {:next_state, :confirmed, data}
    end
  end

  def completed(:cast, {:error, reason}, data), do: shutdown(reason, data)

  def confirmed(:enter, _old_state, %{transport: transport} = data) do
    if Transport.reliable(transport) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timerI, nil}]}  # start timer I
    end
  end

  def confirmed(:state_timeout, _nil, data), do: {:stop, :normal, data}

  def confirmed(:cast, {:incoming_request, _request}, _data),
    do: :keep_state_and_data
end

defmodule Sippet.ServerTransaction.NonInvite do
  def start_link(user, request, transport) do
    :gen_statem.start_link(__MODULE__, %{user: user,
                                         request: request,
                                         transport: transport}, [])
  end

  def callback_mode(), do: [:state_functions, :state_enter]

  def init(data), do: {:ok, :calling, data}

end
