defmodule Sippet.TransactionLayer do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  def start_link(user, %Message{start_line: %RequestLine{method: method}} = request,
      transport) do
    case method do
      :invite ->
        ClientInvite.start_link(user, request, transport)
      _otherwise ->
        ClientNonInvite.start_link(user, request, transport)
    end
  end

  def start_link(user, %Message{start_line: %StatusLine{}} = response,
      transport) do
    {_sequence, method} = response.headers.cseq
    case method do
      :invite ->
        ServerInvite.start_link(user, response, transport)
      _otherwise ->
        ServerNonInvite.start_link(user, response, transport)
    end
  end
end

defmodule Sippet.TransactionLayer.ClientInvite do
  alias Sippet.Message, as: Message
  alias Sippet.Transport, as: Transport
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.ClientTransaction.User, as: User

  @timerA 600  # optimization: transaction ends in 37.8s
  @timerB 64 * @timerA
  @timerD 32000  # timer D should be > 32s

  def start_link(user, request, transport) do
    :gen_statem.start_link(__MODULE__, %{user: user,
                                         request: request,
                                         transport: transport}, [])
  end

  def callback_mode(), do: [:state_functions, :state_enter]

  defp shutdown(reason, %{user: user} = data) do
    User.on_error(user, reason)
    {:stop, :shutdown, data}
  end

  def init(%{transport: transport} = data) do
    actions = if Transport.reliable(transport) do
        [{:state_timeout, @timerB,
          %{last: @timerB, passed: @timerB}}]  # start timer B
      else
        [{:state_timeout, @timerA,
          %{last: @timerA, passed: @timerA}}]  # start timer A
      end
    {:ok, :calling, data, actions}
  end

  def calling(:enter, _old_state, %{request: request, transport: transport}) do
    Transport.send(transport, request)
    :keep_state_and_data
  end

  def calling(:state_timeout, %{last: l, passed: t}, data) do
    if t >= @timerB do
      shutdown(:timeout, data)
    else
      new_delay = l * 2
      {:repeat_state_and_data, [{:state_timeout, new_delay,
         %{last: new_delay, passed: t + new_delay}}]}
    end
  end

  def calling(:cast, {:incoming_response, response}, %{user: user} = data) do
    User.on_response(user, response)
    case StatusLine.status_code_class(response.start_line) do
      1 ->
        {:next_state, :proceeding, data}
      2 ->
        {:stop, :normal, data}
      _otherwise ->
        {:next_state, :completed, data}
    end
  end

  def calling(:cast, {:error, reason}, data) do
    shutdown(reason, data)
  end

  def proceeding(:enter, _old_state, _data), do: :keep_state_and_data

  def proceeding(:cast, {:incoming_response, response},
      %{user: user} = data) do
    User.on_response(user, response)
    case StatusLine.status_code_class(response.start_line) do
      1 ->
        :keep_state_and_data
      2 ->
        {:stop, :normal, data}
      _otherwise ->
        {:next_state, :completed, data}
    end
  end

  def completed(:enter, _old_state,
      %{request: request, transport: transport} = data) do
    ack = do_build_ack(request)
    data = Map.put(data, :ack, ack)
    Transport.send(transport, ack)
    if Transport.reliable(transport) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timerD, []}]}  # start timer D
    end
  end

  def completed(:cast, {:incoming_response, response},
      %{ack: ack, transport: transport}) do
    if StatusLine.status_code_class(response.start_line) >= 3 do
      Transport.send(transport, ack)
    end
    :keep_state_and_data
  end

  def completed(:cast, {:error, reason}, data), do: shutdown(reason, data)

  def completed(:state_timeout, _ignore, data), do: {:stop, :normal, data}

  defp do_build_ack(_request) do
    #TODO(guibv): build the ACK request using the original request
    :ok
  end
end

defmodule Sippet.TransactionLayer.ClientNonInvite do
  alias Sippet.Message, as: Message
  alias Sippet.Transport, as: Transport
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.ClientTransaction.User, as: User

  @t2 4000
  @timerE 600  # optimization: transaction ends in 35.5s
  @timerF 64 * @timerE
  @timerK 5000  # timer K is 5s

  def start_link(user, request, transport) do
    :gen_statem.start_link(__MODULE__, %{user: user,
                                         request: request,
                                         transport: transport}, [])
  end

  def callback_mode(),
    do: [:state_functions, :state_enter]

  def init(data), do: {:ok, :trying, data}

  defp start_timers(%{transport: transport} = data) do
    data = Map.put(data, :deadline_timer,
        :erlang.start_timer(@timerF, self(), :deadline))
    if Transport.reliable(transport) do
      data
    else
      Map.put(data, :retry_timer,
          :erlang.start_timer(@timerE, self(), @timerE))
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

  defp timeout(data), do: shutdown(:timeout, data)

  defp retry(next_wait, %{request: request, transport: transport} = data) do
    Transport.send(transport, request)
    data = %{data | retry_timer:
        :erlang.start_timer(next_wait, self(), next_wait)}
    {:keep_state, data}
  end

  defp shutdown(reason, %{user: user} = data) do
    User.on_error(user, reason)
    data = cancel_timers(data)
    {:stop, :shutdown, data}
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
      1 ->
        {:next_state, :proceeding, data}
      _otherwise ->
        {:next_state, :completed, data}
    end
  end

  def trying(:cast, {:error, reason}, data), do: shutdown(reason, data)

  def proceeding(:enter, _old_state, _data), do: :keep_state_and_data

  def proceeding(:info, {:timeout, _timer, :deadline}, data), do: timeout(data)

  def proceeding(:info, {:timeout, _timer, _last_delay}, data),
    do: retry(@t2, data)

  def proceeding(:cast, {:incoming_response, response},
      %{user: user} = data) do
    User.on_response(user, response)
    case StatusLine.status_code_class(response.start_line) do
      1 ->
        :keep_state_and_data
      _otherwise ->
        {:next_state, :completed, data}
    end
  end

  def proceeding(:cast, {:error, reason}, data), do: shutdown(reason, data)

  def completed(:enter, _old_state, %{transport: transport} = data) do
    data = cancel_timers(data)
    if Transport.reliable(transport) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timerK, []}]}  # start timer K
    end
  end

  def completed(:cast, _event_content, _data), do: :keep_state_and_data

  def completed(:state_timeout, _ignore, data), do: {:stop, :normal, data}
end

defmodule Sippet.TransactionLayer.ServerInvite do
  def start_link(_user, _message, _transport) do
  end
end

defmodule Sippet.TransactionLayer.ServerNonInvite do
  def start_link(_user, _message, _transport) do
  end
end

defimpl Sippet.ClientTransaction, for: Sippet.TransactionLayer do
  alias Sippet.Message, as: Message
  alias Sippet.Message.StatusLine, as: StatusLine

  def on_response(pid, %Message{start_line: %StatusLine{}} = response)
      when is_pid(pid) do
    :gen_statem.cast(pid, {:incoming_response, response})
  end

  def on_error(pid, reason) when is_pid(pid) and is_atom(reason) do
    :gen_statem.cast(pid, {:error, reason})
  end
end

defimpl Sippet.ServerTransaction, for: Sippet.TransactionLayer do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

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
