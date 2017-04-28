defmodule Sippet.Transactions.Client.NonInvite do
  @moduledoc false

  use Sippet.Transactions.Client, initial_state: :trying

  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.Transactions.Client.State, as: State

  require Logger

  @t2 4000
  @timer_e 500
  @timer_f 64 * @timer_e
  @timer_k 5000  # timer K is 5s

  defp start_timers(%State{request: request, extras: extras} = data) do
    deadline_timer = self() |> Process.send_after(:deadline, @timer_f)
    extras = extras |> Map.put(:deadline_timer, deadline_timer)

    extras =
      if reliable?(request) do
        extras
      else
        retry_timer = self() |> Process.send_after(@timer_e, @timer_e)
        extras |> Map.put(:retry_timer, retry_timer)
      end

    %{data | extras: extras}
  end

  defp cancel_timers(%State{extras: extras} = data) do
    extras =
      case extras do
        %{deadline_timer: deadline_timer} ->
          deadline_timer |> Process.cancel_timer()
          extras |> Map.delete(:deadline_timer)
        _ ->
          extras
      end

    extras =
      case extras do
        %{retry_timer: retry_timer} ->
          retry_timer |> Process.cancel_timer()
          extras |> Map.delete(:retry_timer)
        _ ->
          extras
      end

    %{data | extras: extras}
  end

  defp retry(next_wait, %State{request: request, extras: extras} = data) do
    send_request(request, data)
    extras = extras |> Map.put(:retry_timer,
        self() |> Process.send_after(next_wait, next_wait))
    {:keep_state, %{data | extras: extras}}
  end

  def trying(:enter, _old_state, %State{request: request} = data) do
    send_request(request, data)
    {:keep_state, start_timers(data)}
  end

  def trying(:info, {:timeout, _timer, :deadline}, data),
    do: timeout(data)

  def trying(:info, {:timeout, _timer, last_delay}, data),
    do: retry(min(last_delay * 2, @t2), data)

  def trying(:cast, {:incoming_response, response}, data) do
    receive_response(response, data)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:next_state, :proceeding, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def trying(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def trying(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)

  def proceeding(:enter, _old_state, _data),
    do: :keep_state_and_data

  def proceeding(:info, {:timeout, _timer, :deadline}, data),
    do: timeout(data)

  def proceeding(:info, {:timeout, _timer, _last_delay}, data),
    do: retry(@t2, data)

  def proceeding(:cast, {:incoming_response, response}, data) do
    receive_response(response, data)
    case StatusLine.status_code_class(response.start_line) do
      1 -> {:keep_state, data}
      _ -> {:next_state, :completed, data}
    end
  end

  def proceeding(:cast, {:error, reason}, data),
    do: shutdown(reason, data)

  def proceeding(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)

  def completed(:enter, _old_state, %State{request: request} = data) do
    data = cancel_timers(data)
    if reliable?(request) do
      {:stop, :normal, data}
    else
      {:keep_state, data, [{:state_timeout, @timer_k, nil}]}
    end
  end

  def completed(:state_timeout, _nil, data),
    do: {:stop, :normal, data}

  def completed(:cast, {:incoming_response, _response}, _data),
    do: :keep_state_and_data

  def completed(:cast, {:error, _reason}, _data),
    do: :keep_state_and_data

  def completed(event_type, event_content, data),
    do: unhandled_event(event_type, event_content, data)
end
