defmodule Sippet.Transactions.Server.Invite do
  @moduledoc false

  use Sippet.Transactions.Server, initial_state: :proceeding

  alias Sippet.Message
  alias Sippet.Message.StatusLine
  alias Sippet.Transactions.Server.State

  @t2 4_000
  @before_trying 200
  @timer_g 500
  @timer_h 64 * @timer_g

  # timer I is 5s
  @timer_i 5_000

  def init(%State{key: key, sippet: sippet} = data) do
    # add an alias for incoming ACK requests for status codes != 200
    Registry.register(sippet, {:transaction, %{key | method: :ack}}, nil)

    super(data)
  end

  defp retry(
         {past_wait, passed_time},
         %State{extras: %{last_response: last_response}} = data
       ) do
    send_response(last_response, data)
    new_delay = min(past_wait * 2, @t2)
    {:keep_state_and_data, [{:state_timeout, new_delay, {new_delay, passed_time + new_delay}}]}
  end

  def proceeding(:enter, _old_state, %State{request: request} = data) do
    receive_request(request, data)
    {:keep_state_and_data, [{:state_timeout, @before_trying, :still_trying}]}
  end

  def proceeding(:state_timeout, :still_trying, %State{request: request} = data) do
    response = request |> Message.to_response(100)
    data = send_response(response, data)
    {:keep_state, data}
  end

  def proceeding(
        :cast,
        {:incoming_request, _request},
        %State{extras: %{last_response: last_response}} = data
      ) do
    send_response(last_response, data)
    :keep_state_and_data
  end

  def proceeding(:cast, {:incoming_request, _request}, _data),
    do: :keep_state_and_data

  def proceeding(:cast, {:outgoing_response, response}, data) do
    data = send_response(response, data)

    case StatusLine.status_code_class(response.start_line) do
      1 -> {:keep_state, data}
      2 -> {:stop, :normal, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def proceeding(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def proceeding(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)

  def completed(:enter, _old_state, %State{request: request} = data) do
    actions =
      if reliable?(request, data) do
        [{:state_timeout, @timer_h, {@timer_h, @timer_h}}]
      else
        [{:state_timeout, @timer_g, {@timer_g, @timer_g}}]
      end

    {:keep_state_and_data, actions}
  end

  def completed(:state_timeout, time_event, data) do
    {_past_wait, passed_time} = time_event

    if passed_time >= @timer_h do
      timeout(data)
    else
      retry(time_event, data)
    end
  end

  def completed(
        :cast,
        {:incoming_request, request},
        %State{extras: %{last_response: last_response}} = data
      ) do
    case request.start_line.method do
      :invite ->
        send_response(last_response, data)
        :keep_state_and_data

      :ack ->
        {:next_state, :confirmed, data}

      _otherwise ->
        shutdown(:invalid_method, data)
    end
  end

  def completed(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def completed(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)

  def confirmed(:enter, _old_state, %State{request: request} = data) do
    if reliable?(request, data) do
      {:stop, :normal, data}
    else
      {:keep_state_and_data, [{:state_timeout, @timer_i, nil}]}
    end
  end

  def confirmed(:state_timeout, _nil, data),
    do: {:stop, :normal, data}

  def confirmed(:cast, {:incoming_request, _request}, _data),
    do: :keep_state_and_data

  def confirmed(:cast, {:error, _reason}, _data),
    do: :keep_state_and_data

  def confirmed(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)
end
