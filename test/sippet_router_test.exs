defmodule Sippet.Router.Test do
  use ExUnit.Case, async: false

  import Mock

  alias Sippet.Transactions.Server.State

  test "incoming datagram, empty body" do
    with_mocks [
      {Registry, [],
       [
         lookup: fn _, _ -> [] end
       ]},
      {Supervisor, [],
       [
         start_child: fn _, {_, [%State{request: %{body: ""}}, _]} ->
           {:ok, self()}
         end
       ]}
    ] do
      from = {:tls, {10, 10, 1, 1}, 5060}

      packet = """
      REGISTER sips:ss2.biloxi.example.com SIP/2.0
      Via: SIP/2.0/TLS client.biloxi.example.com:5061;branch=z9hG4bKnashds7
      Max-Forwards: 70
      From: Bob <sips:bob@biloxi.example.com>;tag=a73kszlfl
      To: Bob <sips:bob@biloxi.example.com>
      Call-ID: 1j9FpLxk3uxtm8tn@biloxi.example.com
      CSeq: 1 REGISTER
      Contact: <sips:bob@client.biloxi.example.com>
      Content-Length: 0
      """

      Sippet.Router.handle_transport_message(:sippet, packet, from)

      assert called(Registry.lookup(:sippet, {:transaction, :_}))

      assert called(
               Supervisor.start_child(
                 :sippet_sup,
                 {Sippet.Transactions.Server.NonInvite, :_}
               )
             )
    end
  end

  @test_body """
  v=0
  o=alice 2890844526 2890844526 IN IP4 foo.bar.com
  s=-
  c=IN IP4 192.0.2.101
  t=0 0
  m=audio 49172 RTP/AVP 0
  a=rtpmap:0 PCMU/8000
  """

  test "incoming datagram, with body" do
    with_mocks [
      {Registry, [],
       [
         lookup: fn _, _ -> [] end
       ]},
      {Supervisor, [],
       [
         start_child: fn _, {_, [%State{request: %{body: @test_body}}, _]} ->
           {:ok, self()}
         end
       ]}
    ] do
      from = {:tcp, "10.0.0.73", 12335}

      packet =
        """
        INVITE sip:bob@biloxi.example.com SIP/2.0
        Via: SIP/2.0/TCP client.atlanta.example.com:5060;branch=z9hG4bK74bf9
        Max-Forwards: 70
        From: Alice <sip:alice@atlanta.example.com>;tag=9fxced76sl
        To: Bob <sip:bob@biloxi.example.com>
        Call-ID: 3848276298220188511@atlanta.example.com
        CSeq: 1 INVITE
        Contact: <sip:alice@client.atlanta.example.com;transport=tcp>
        Content-Type: application/sdp
        Content-Length: #{@test_body |> String.length()}

        """ <> @test_body

      Sippet.Router.handle_transport_message(:sippet, packet, from)

      assert called(Registry.lookup(:sippet, {:transaction, :_}))

      assert called(
               Supervisor.start_child(
                 :sippet_sup,
                 {Sippet.Transactions.Server.Invite, :_}
               )
             )
    end
  end

  test "missing required headers" do
    with_mocks [
      {Registry, [],
       [
         lookup: fn _, _ -> [] end
       ]},
      {Supervisor, [],
       [
         start_child: fn _, _ -> {:ok, self()} end
       ]}
    ] do
      from = {:tcp, "10.0.0.73", 12335}

      packet = """
      REGISTER sips:ss2.biloxi.example.com SIP/2.0
      Via: SIP/2.0/TLS client.biloxi.example.com:5061;branch=z9hG4bKnashds7
      Max-Forwards: 70
      Call-ID: 1j9FpLxk3uxtm8tn@biloxi.example.com
      CSeq: 1 REGISTER
      Contact: <sips:bob@client.biloxi.example.com>
      Content-Length: 0
      """

      Sippet.Router.handle_transport_message(:sippet, packet, from)

      assert not called(Registry.lookup(:_, :_))
    end
  end

  test "invalid message" do
    with_mocks [
      {Registry, [],
       [
         lookup: fn _, _ -> [] end
       ]},
      {Supervisor, [],
       [
         start_child: fn _, _ -> {:ok, self()} end
       ]}
    ] do
      from = {:tcp, "10.0.0.73", 12335}

      packet = """
      REGISTER SIP/2.0
      """

      Sippet.Router.handle_transport_message(:sippet, packet, from)

      assert not called(Registry.lookup(:_, :_))
    end
  end
end
