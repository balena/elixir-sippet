defmodule Sippet.Transaction.Client.NonInvite.Test do
  use ExUnit.Case, async: false

  alias Sippet.Message
  alias Sippet.Transaction.Client
  alias Sippet.Transaction.Client.State
  alias Sippet.Transaction.Client.NonInvite

  import Mock

  setup do
    request =
      """
      REGISTER sip:registrar.biloxi.com SIP/2.0
      Via: SIP/2.0/UDP bobspc.biloxi.com:5060;branch=z9hG4bKnashds7
      Max-Forwards: 70
      To: Bob <sip:bob@biloxi.com>
      From: Bob <sip:bob@biloxi.com>;tag=456248
      Call-ID: 843817637684230@998sdasdh09
      CSeq: 1826 REGISTER
      Contact: <sip:bob@192.0.2.4>
      Expires: 7200
      """
      |> Message.parse!()

    transaction = Client.new(request)
    state = State.new(request, transaction)

    {:ok, %{request: request, transaction: transaction, state: state}}
  end

  test "client transaction data", %{transaction: transaction} do
    assert transaction.branch == "z9hG4bKnashds7"
    assert transaction.method == :register
  end

  test "client non-invite trying state",
      %{request: request, transaction: transaction, state: state} do
    # test if the retry timer has been started for unreliable transports, and
    # if the received request is sent to the core
    with_mocks([
        {Sippet.Transport, [],
          [send_message: fn _, _ -> :ok end,
           reliable?: fn _ -> false end]},
        {Sippet.Core, [],
          [receive_response: fn _, _ -> :ok end,
           receive_error: fn _, _ -> :ok end]}]) do

      {:keep_state, data} =
          NonInvite.trying(:enter, :none, state)

      assert data_timeout data, :retry_timer, 500
      assert data_timeout data, :deadline_timer, 64 * 500

      assert called Sippet.Transport.reliable?(request)
      assert called Sippet.Transport.send_message(request, transaction)

      # the retry timer should send the request again and double the retry
      # timer
      {:keep_state, data} =
          NonInvite.trying(:info, {:timeout, 500, 500}, data)

      assert data_timeout data, :retry_timer, 1000
      assert called Sippet.Transport.send_message(request, transaction)

      # the deadline timer should terminate the process and send timeout
      # to core
      {:stop, :shutdown, _data} =
          NonInvite.trying(:info, {:timeout, 64 * 500, :deadline}, data)

      assert called Sippet.Core.receive_error(:timeout, transaction)

      # in the transition to the proceeding state, the timers aren't stopped
      last_response = Message.build_response(request, 100)

      {:next_state, :proceeding, data} =
          NonInvite.trying(:cast, {:incoming_response, last_response}, data)

      assert data_timeout data, :retry_timer
      assert data_timeout data, :deadline_timer

      # timers are cancelled only when entering the completed state
      {:keep_state, data, actions} =
          NonInvite.completed(:enter, :proceeding, data)

      assert not data_timeout data, :retry_timer
      assert not data_timeout data, :deadline_timer

      assert action_timeout actions, 5000
    end
  end

  defp data_timeout(%{extras: extras}, name) do
    extras |> Map.has_key?(name)
  end

  defp data_timeout(%{extras: extras} = data, name, interval) do
    data_timeout(data, name) and
      extras[name] |> Process.read_timer() == interval
  end

  defp action_timeout(actions, delay) do
    timeout_actions =
      for x <- actions,
          {:state_timeout, ^delay, _data} = x do
        x
      end

    assert length(timeout_actions) == 1
  end
end
