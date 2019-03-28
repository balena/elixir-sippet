defmodule Sippet.Transports.Worker.Test do
  use ExUnit.Case, async: false

  alias Sippet.Transports.Worker, as: Worker

  import Mock

  test "incoming datagram, empty body" do
    with_mocks [
      {Sippet.Transports.Pool, [], [check_in: fn _ -> :ok end]},
      {Sippet.Transactions, [],
       [
         receive_message: fn msg ->
           assert msg.body == ""
           :ok
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

      msg = {:incoming_datagram, packet, from}
      {:noreply, _} = Worker.handle_cast(msg, nil)

      assert called(Sippet.Transports.Pool.check_in(self()))
      assert called(Sippet.Transactions.receive_message(:_))
    end
  end

  @test_body ~s{v=0\r\n} <>
               ~s{o=alice 2890844526 2890844526 IN IP4 foo.bar.com\r\n} <>
               ~s{s=-\r\n} <>
               ~s{c=IN IP4 192.0.2.101\r\n} <>
               ~s{t=0 0\r\n} <> ~s{m=audio 49172 RTP/AVP 0\r\n} <> ~s{a=rtpmap:0 PCMU/8000\r\n}

  test "incoming datagram, with body" do
    with_mocks [
      {Sippet.Transports.Pool, [], [check_in: fn _ -> :ok end]},
      {Sippet.Transactions, [],
       [
         receive_message: fn msg ->
           assert msg.body == @test_body
           :ok
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
        Content-Length: 136

        """ <> @test_body

      msg = {:incoming_datagram, packet, from}
      {:noreply, _} = Worker.handle_cast(msg, nil)

      assert called(Sippet.Transports.Pool.check_in(self()))
      assert called(Sippet.Transactions.receive_message(:_))
    end
  end

  test "missing required headers" do
    with_mocks [
      {Sippet.Transports.Pool, [], [check_in: fn _ -> :ok end]},
      {Sippet.Transactions, [],
       [
         receive_message: fn msg ->
           assert msg.body == @test_body
           :ok
         end
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

      msg = {:incoming_datagram, packet, from}
      {:noreply, _} = Worker.handle_cast(msg, nil)

      assert called(Sippet.Transports.Pool.check_in(self()))
      assert not called(Sippet.Transactions.receive_message(:_))
    end
  end

  test "invalid message" do
    with_mocks [
      {Sippet.Transports.Pool, [], [check_in: fn _ -> :ok end]},
      {Sippet.Transactions, [],
       [
         receive_message: fn msg ->
           assert msg.body == @test_body
           :ok
         end
       ]}
    ] do
      from = {:tcp, "10.0.0.73", 12335}

      packet = """
      REGISTER SIP/2.0
      """

      msg = {:incoming_datagram, packet, from}
      {:noreply, _} = Worker.handle_cast(msg, nil)

      assert called(Sippet.Transports.Pool.check_in(self()))
      assert not called(Sippet.Transactions.receive_message(:_))
    end
  end
end
