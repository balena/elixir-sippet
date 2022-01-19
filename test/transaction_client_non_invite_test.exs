defmodule Sippet.Transactions.Client.NonInvite.Test do
  use ExUnit.Case, async: false

  alias Sippet.Message
  alias Sippet.Transactions.Client
  alias Sippet.Transactions.Client.State
  alias Sippet.Transactions.Client.NonInvite

  import Mock

  defmacro action_timeout(actions, delay) do
    quote do
      unquote(actions)
      |> Enum.count(fn x ->
        case x do
          {:state_timeout, unquote(delay), _data} -> true
          _otherwise -> false
        end
      end)
    end
  end

  defmacro data_timeout(data, name) do
    quote do
      unquote(data).extras |> Map.has_key?(unquote(name))
    end
  end

  defmacro data_timeout(data, name, interval) do
    quote do
      data_timeout(unquote(data), unquote(name)) and
        unquote(data).extras[unquote(name)]
        |> Process.read_timer() == unquote(interval)
    end
  end

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

    transaction = Client.Key.new(request)
    state = State.new(request, transaction, :sippet)

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
      {Sippet.Router, [],
       [
         to_core: fn _, _, _ -> :ok end,
         send_transport_message: fn _, _, _ -> :ok end
       ]},
      {Sippet, [],
       [
         reliable?: fn _, _ -> false end
       ]}
    ]) do
      {:keep_state, data} = NonInvite.trying(:enter, :none, state)

      assert data_timeout(data, :retry_timer, 500)
      assert data_timeout(data, :deadline_timer, 64 * 500)

      assert called(Sippet.reliable?(:sippet, request))
      assert called(Sippet.Router.send_transport_message(:sippet, request, transaction))

      # the retry timer should send the request again and double the retry
      # timer
      {:keep_state, data} = NonInvite.trying(:info, 500, data)

      assert data_timeout(data, :retry_timer, 1000)
      assert called(Sippet.Router.send_transport_message(:sippet, request, transaction))

      # the deadline timer should terminate the process and send timeout
      # to core
      {:stop, :shutdown, _data} = NonInvite.trying(:info, :deadline, data)

      assert called(Sippet.Router.to_core(:sippet, :receive_error, [:timeout, transaction]))

      # in the transition to the proceeding state, the timers aren't stopped
      last_response = Message.to_response(request, 100)

      {:next_state, :proceeding, data} =
        NonInvite.trying(:cast, {:incoming_response, last_response}, data)

      assert data_timeout(data, :retry_timer)
      assert data_timeout(data, :deadline_timer)

      # timers are cancelled only when entering the completed state
      {:keep_state, data, actions} = NonInvite.completed(:enter, :proceeding, data)

      assert not data_timeout(data, :retry_timer)
      assert not data_timeout(data, :deadline_timer)

      assert action_timeout(actions, 5000)
    end
  end
end
