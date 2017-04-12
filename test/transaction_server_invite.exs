defmodule Sippet.Transaction.Server.Invite do
  use ExUnit.Case, async: false

  alias Sippet.Message
  alias Sippet.Transaction.Server
  alias Sippet.Transaction.Server.State
  alias Sippet.Transaction.Server.Invite

  import Mock

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

    transaction = Server.new(request)
    state = State.new(request, transaction)

    {:ok, %{request: request, transaction: transaction, state: state}}
  end

  test "server transaction data", %{transaction: transaction} do
    assert transaction.branch == "z9hG4bK776asdhds"
    assert transaction.method == :invite
    assert transaction.sent_by == {"pc33.atlanta.com", 5060}
  end

  test "client invite proceeding state",
      %{request: request, transaction: transaction, state: state} do
    # test if the retry timer has been started for unreliable transports, and
    # if the received request is sent to the core
    with_mock Sippet.Transport,
        [send_message: fn _, _ -> :ok end,
         reliable?: fn _ -> false end] do

      {:keep_state_and_data, actions} =
          Invite.proceeding(:enter, :none, state)

      # ensure that a timer of 200ms is started in order to send a 100 Trying
      # automatically
      assert action_timeout actions, 200

      assert called Sippet.Core.receive_request(request, transaction)

      # case another request is sent before this 200ms timer, then no response
      # is sent
      :keep_state_and_data =
          Invite.proceeding(:cast, {:incoming_request, request}, data)

      response = request |> Message.build_response(100)
      assert not called Sippet.Transport.send_response(response, transaction)

      # ensure that the 100 Trying is created and sent automatically
      {:keep_state, data, actions} =
          Invite.proceeding(:state_timeout, :still_trying, data)

      assert data.extras |> Map.has_key?(:last_response)

      last_response = data.extras.last_response
      assert called Sippet.Transport.send_response(last_response, transaction)

      # ensure that the state machine finishes case the idle timer fires
      {:stop, :shutdown, _data} =
          Invite.proceeding(:state_timeout, :idle, data)

      # while retrying, the response has to be sent
      :keep_state_and_data =
          Invite.proceeding(:cast, {:incoming_request, request}, data)

      assert called Sippet.Transport.send_response(last_response, transaction)
    end
  end
end
