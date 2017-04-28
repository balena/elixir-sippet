defmodule Sippet.Transactions.Server.Invite.Test do
  use ExUnit.Case, async: false

  alias Sippet.Message
  alias Sippet.Transactions.Server
  alias Sippet.Transactions.Server.State
  alias Sippet.Transactions.Server.Invite

  import Mock

  defmacro action_timeout(actions, delay) do
    quote do
      unquote(actions) |> Enum.count(
        fn x ->
          case x do
            {:state_timeout, unquote(delay), _data} -> true
            _otherwise -> false
          end
        end)
    end
  end

  setup do
    request =
      """
      INVITE sip:bob@biloxi.com SIP/2.0
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds
      Max-Forwards: 70
      To: Bob <sip:bob@biloxi.com>
      From: Alice <sip:alice@atlanta.com>;tag=1928301774
      Call-ID: a84b4c76e66710@pc33.atlanta.com
      CSeq: 314159 INVITE
      Contact: <sip:alice@pc33.atlanta.com>
      """
      |> Message.parse!()

    transaction = Server.Key.new(request)
    data = State.new(request, transaction)

    {:ok, %{request: request, transaction: transaction, data: data}}
  end

  test "server transaction data", %{transaction: transaction} do
    assert transaction.branch == "z9hG4bK776asdhds"
    assert transaction.method == :invite
    assert transaction.sentby == {"pc33.atlanta.com", 5060}
  end

  test "server invite proceeding state",
      %{request: request, transaction: transaction, data: data} do
    with_mocks([
        {Sippet.Transports, [],
          [send_message: fn _, _ -> :ok end,
           reliable?: fn _ -> false end]},
        {Sippet.Core, [],
          [receive_request: fn _, _ -> :ok end,
           receive_error: fn _, _ -> :ok end]}]) do

      # test if the retry timer has been started for unreliable transports, and
      # if the received request is sent to the core
      {:keep_state_and_data, actions} =
          Invite.proceeding(:enter, :none, data)

      # ensure that a timer of 200ms is started in order to send a 100 Trying
      # automatically
      assert action_timeout actions, 200

      assert called Sippet.Core.receive_request(request, transaction)

      # case another request is sent before this 200ms timer, then no response
      # is sent
      :keep_state_and_data =
          Invite.proceeding(:cast, {:incoming_request, request}, data)

      response = request |> Message.to_response(100)
      assert not called Sippet.Transports.send_response(response, transaction)

      # ensure that the 100 Trying is created and sent automatically
      {:keep_state, data, _actions} =
          Invite.proceeding(:state_timeout, :still_trying, data)

      assert data.extras |> Map.has_key?(:last_response)

      last_response = data.extras.last_response
      assert called Sippet.Transports.send_message(last_response, transaction)

      # ensure that the state machine finishes case the idle timer fires
      {:stop, :shutdown, _data} =
          Invite.proceeding(:state_timeout, :idle, data)

      # while retrying, the response has to be sent
      :keep_state_and_data =
          Invite.proceeding(:cast, {:incoming_request, request}, data)

      assert called Sippet.Transports.send_message(last_response, transaction)
    end
  end
end
