defmodule Sippet.Transactions.Client.Invite.Test do
  use ExUnit.Case, async: false

  alias Sippet.Message
  alias Sippet.Transactions.Client
  alias Sippet.Transactions.Client.State
  alias Sippet.Transactions.Client.Invite

  import Mock

  defmacro action_timeout(actions, delay) do
    quote do
      unquote(actions)
      |> Enum.count(fn x ->
        interval = unquote(delay)

        case x do
          {:state_timeout, ^interval, _data} -> true
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

    transaction = Client.Key.new(request)
    state = State.new(request, transaction, :sippet)

    {:ok, %{request: request, transaction: transaction, state: state}}
  end

  test "client transaction data", %{transaction: transaction} do
    assert transaction.branch == "z9hG4bK776asdhds"
    assert transaction.method == :invite
  end

  test "client invite calling state",
       %{request: request, transaction: transaction, state: state} do
    # test if the retry timer has been started for unreliable transports, and
    # if the received request is sent to the core
    with_mocks [
      {Sippet.Router, [],
       [
         send_transport_message: fn _, _, _ -> :ok end
       ]},
      {Sippet, [],
       [
         reliable?: fn _, _ -> false end
       ]}
    ] do
      {:keep_state_and_data, actions} = Invite.calling(:enter, :none, state)

      assert action_timeout(actions, 600)

      assert called(Sippet.reliable?(:sippet, request))
      assert called(Sippet.Router.send_transport_message(:sippet, request, transaction))
    end

    # test if the timeout timer has been started for reliable transports
    with_mocks [
      {Sippet.Router, [],
       [
         send_transport_message: fn _, _, _ -> :ok end
       ]},
      {Sippet, [],
       [
         reliable?: fn _, _ -> true end
       ]}
    ] do
      {:keep_state_and_data, actions} = Invite.calling(:enter, :none, state)

      assert action_timeout(actions, 64 * 600)

      assert called(Sippet.reliable?(:sippet, request))
      assert called(Sippet.Router.send_transport_message(:sippet, request, transaction))
    end

    # test timer expiration for unreliable transports
    with_mocks [
      {Sippet.Router, [],
       [
         send_transport_message: fn _, _, _ -> :ok end
       ]},
      {Sippet, [],
       [
         reliable?: fn _, _ -> false end
       ]}
    ] do
      {:keep_state_and_data, actions} = Invite.calling(:state_timeout, {1200, 1200}, state)

      assert action_timeout(actions, 2400)

      assert called(Sippet.Router.send_transport_message(:sippet, request, transaction))
    end

    # test timeout and errors
    with_mock Sippet.Router, to_core: fn _, _, _ -> :ok end do
      {:stop, :shutdown, _data} = Invite.calling(:state_timeout, {6000, 64 * 600}, state)

      {:stop, :shutdown, _data} = Invite.calling(:cast, {:error, :uh_oh}, state)
    end

    ## test state transitions that depend on the reception of responses with
    ## different status codes
    with_mock Sippet.Router, to_core: fn _, _, _ -> :ok end do
      response = Message.to_response(request, 100)

      {:next_state, :proceeding, _data} =
        Invite.calling(:cast, {:incoming_response, response}, state)

      response = Message.to_response(request, 200)
      {:stop, :normal, _data} = Invite.calling(:cast, {:incoming_response, response}, state)

      response = Message.to_response(request, 400)

      {:next_state, :completed, _data} =
        Invite.calling(:cast, {:incoming_response, response}, state)
    end
  end

  test "client invite proceeding state",
       %{request: request, state: state} do
    # check state transitions depending on the received responses
    with_mock Sippet.Router, to_core: fn _, _, _ -> :ok end do
      :keep_state_and_data = Invite.proceeding(:enter, :calling, state)

      response = Message.to_response(request, 180)
      {:keep_state, _data} = Invite.proceeding(:cast, {:incoming_response, response}, state)
      assert called(Sippet.Router.to_core(:sippet, :receive_response, [response, :_]))

      response = Message.to_response(request, 200)
      {:stop, :normal, _data} = Invite.proceeding(:cast, {:incoming_response, response}, state)
      assert called(Sippet.Router.to_core(:sippet, :receive_response, [response, :_]))

      response = Message.to_response(request, 400)

      {:next_state, :completed, _data} =
        Invite.proceeding(:cast, {:incoming_response, response}, state)

      assert called(Sippet.Router.to_core(:sippet, :receive_response, [response, :_]))
    end

    # this is not part of the standard, but may occur in exceptional cases
    with_mock Sippet.Router, to_core: fn _, _, _ -> :ok end do
      {:stop, :shutdown, _data} = Invite.proceeding(:cast, {:error, :uh_oh}, state)
      assert called(Sippet.Router.to_core(:sippet, :receive_error, :_))
    end
  end

  test "client invite completed state",
       %{request: request, transaction: transaction, state: state} do
    # test the ACK request creation
    with_mocks [
      {Sippet.Router, [],
       [
         send_transport_message: fn _, _, _ -> :ok end
       ]},
      {Sippet, [],
       [
         reliable?: fn _, _ -> false end
       ]}
    ] do
      last_response = Message.to_response(request, 400)
      %{extras: extras} = state
      extras = extras |> Map.put(:last_response, last_response)

      {:keep_state, data, actions} =
        Invite.completed(:enter, :proceeding, %{state | extras: extras})

      assert action_timeout(actions, 32000)

      %{extras: %{ack: ack}} = data
      assert :ack == ack.start_line.method
      assert :ack == ack.headers.cseq |> elem(1)

      # ACK is retransmitted case another response comes in
      :keep_state_and_data = Invite.completed(:cast, {:incoming_response, last_response}, data)

      assert called(Sippet.Router.send_transport_message(:sippet, ack, transaction))
    end

    # reliable transports don't keep the completed state
    with_mocks [
      {Sippet.Router, [],
       [
         send_transport_message: fn _, _, _ -> :ok end
       ]},
      {Sippet, [],
       [
         reliable?: fn _, _ -> true end
       ]}
    ] do
      last_response = Message.to_response(request, 400)
      %{extras: extras} = state
      extras = extras |> Map.put(:last_response, last_response)

      {:stop, :normal, data} = Invite.completed(:enter, :proceeding, %{state | extras: extras})

      %{extras: %{ack: ack}} = data
      assert :ack == ack.start_line.method
      assert :ack == ack.headers.cseq |> elem(1)
    end

    # check state completion after timer D
    {:stop, :normal, nil} = Invite.completed(:state_timeout, nil, nil)
  end
end
