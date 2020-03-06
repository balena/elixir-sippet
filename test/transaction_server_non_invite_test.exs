defmodule Sippet.Transactions.Server.NonInvite.Test do
  use ExUnit.Case, async: false

  alias Sippet.Message
  alias Sippet.Transactions.Server
  alias Sippet.Transactions.Server.State
  alias Sippet.Transactions.Server.NonInvite

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

    transaction = Server.Key.new(request)
    data = State.new(request, transaction, :sippet)

    {:ok, %{request: request, transaction: transaction, data: data}}
  end

  test "server non-invite trying state",
       %{request: request, transaction: transaction, data: data} do
    with_mocks [
      {Sippet.Router, [],
       [
         to_core: fn _, _, _ -> :ok end
       ]},
      {Sippet, [],
       [
         reliable?: fn _, _ -> false end
       ]}
    ] do
      # the core will have up to 4 seconds to answer the incoming request
      :keep_state_and_data = NonInvite.trying(:enter, :none, data)

      assert called(Sippet.Router.to_core(:sippet, :receive_request, [request, transaction]))
    end

    ## error conditions are timeout and network errors
    with_mock Sippet.Router, to_core: fn _, _, _ -> :ok end do
      {:stop, :shutdown, _data} = NonInvite.trying(:cast, {:error, :uh_oh}, data)
      assert called(Sippet.Router.to_core(:sippet, :receive_error, [:uh_oh, transaction]))
    end

    # while in trying state, there's no answer, so no retransmission is made
    :keep_state_and_data = NonInvite.trying(:cast, {:incoming_request, request}, data)
  end
end
