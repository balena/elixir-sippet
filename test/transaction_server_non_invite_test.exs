defmodule Sippet.Transaction.Server.NonInvite.Test do
  use ExUnit.Case, async: false

  alias Sippet.Message
  alias Sippet.Transaction.Server
  alias Sippet.Transaction.Server.State
  alias Sippet.Transaction.Server.NonInvite

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

    transaction = Server.new(request)
    data = State.new(request, transaction)

    {:ok, %{request: request, transaction: transaction, data: data}}
  end

  test "server non-invite trying state",
      %{request: request, transaction: transaction, data: data} do
    with_mocks([
        {Sippet.Transport, [],
          [send_message: fn _, _ -> :ok end,
           reliable?: fn _ -> false end]},
        {Sippet.Core, [],
          [receive_request: fn _, _ -> :ok end,
           receive_error: fn _, _ -> :ok end]}]) do

      # the core will have up to 4 seconds to answer the incoming request
      {:keep_state_and_data, actions} =
          NonInvite.trying(:enter, :none, data)

      assert called Sippet.Core.receive_request(request, transaction)
      assert action_timeout actions, 4000
    end

    # error conditions are timeout and network errors
    with_mock Sippet.Core, [receive_error: fn _, _ -> :ok end] do
      {:stop, :shutdown, _data} =
          NonInvite.trying(:state_timeout, nil, data)
      assert called Sippet.Core.receive_error(:idle, transaction)

      {:stop, :shutdown, _data} =
          NonInvite.trying(:cast, {:error, :uh_oh}, data)
      assert called Sippet.Core.receive_error(:uh_oh, transaction)
    end

    # while in trying state, there's no answer, so no retransmission is made
    :keep_state_and_data =
        NonInvite.trying(:cast, {:incoming_request, request}, data)
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
