defmodule Sippet.Transports.Receiver.Test do
  use ExUnit.Case, async: false

  alias Sippet.Transports.Receiver

  import Mock

  test "incoming datagram, empty body" do
    with_mock Sippet.Transactions,
      receive_message: fn %{body: body}, _ ->
        assert body == ""
      end do
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

      :ok = Receiver.receive_raw(packet, from, self())

      assert called(Sippet.Transactions.receive_message(:_, self()))
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
    with_mock Sippet.Transactions,
      receive_message: fn %{body: body}, _ ->
        assert body == @test_body
      end do
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

      :ok = Receiver.receive_raw(packet, from, self())

      assert called(Sippet.Transactions.receive_message(:_, self()))
    end
  end

  test "missing required headers" do
    with_mock Sippet.Transactions,
      receive_message: fn msg, _ ->
        assert msg.body == @test_body
      end do
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

      :ok = Receiver.receive_raw(packet, from, self())

      assert not called(Sippet.Transactions.receive_message(:_, self()))
    end
  end

  test "invalid message" do
    with_mock Sippet.Transactions,
      receive_message: fn msg, _ ->
        assert msg.body == @test_body
      end do
      from = {:tcp, "10.0.0.73", 12335}

      packet = """
      REGISTER SIP/2.0
      """

      :ok = Receiver.receive_raw(packet, from, self())

      assert not called(Sippet.Transactions.receive_message(:_, self()))
    end
  end
end
