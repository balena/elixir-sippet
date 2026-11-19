defmodule Sippet.Message.Test do
  use ExUnit.Case, async: true
  doctest Sippet.Message

  alias Sippet.Message, as: Message

  test "build request" do
    request =
      Message.build_request(
        "REGISTER",
        "sip:registrar.biloxi.com"
      )

    assert Message.request?(request)
  end

  test "build response" do
    response = Message.build_response(200, "OK")
    assert Message.response?(response)
  end

  test "INVITE keeps the telephone subscriber context in Request-URI userinfo" do
    ruri = "sip:3470001234;phone-context=domain@domain;user=phone"
    raw = "INVITE #{ruri} SIP/2.0\r\nContent-Length: 0\r\n\r\n"

    assert {:ok, message} = Message.parse(raw)

    assert %Sippet.URI{
             userinfo: "3470001234;phone-context=domain",
             host: "domain",
             parameters: ";user=phone"
           } = message.start_line.request_uri

    assert to_string(message) == raw
  end

  test "call-waiting Alert-Info survives parsing and serialization" do
    raw =
      "SIP/2.0 180 Ringing\r\n" <>
        "Via: SIP/2.0/UDP 192.0.2.1:5060;branch=z9hG4bKcw\r\n" <>
        "From: <sip:c@ims.test>;tag=c\r\nTo: <sip:b@ims.test>;tag=b\r\n" <>
        "Call-ID: cw\r\nCSeq: 1 INVITE\r\n" <>
        "Alert-Info: <urn:alert:service:call-waiting>\r\nContent-Length: 0\r\n\r\n"

    assert {:ok, msg} = Message.parse(raw)
    assert msg.headers.alert_info == [{"urn:alert:service:call-waiting", %{}}]
    wire = to_string(msg)
    assert wire =~ "Alert-Info: <urn:alert:service:call-waiting>\r\n"
    assert {:ok, reparsed} = Message.parse(wire)
    assert reparsed.headers.alert_info == msg.headers.alert_info
  end

  test "URI info headers preserve brackets, parameters and multiple values" do
    for {key, name} <- [
          {:alert_info, "Alert-Info"},
          {:call_info, "Call-Info"},
          {:error_info, "Error-Info"}
        ] do
      values = [
        {"https://example.com/first", %{"purpose" => "icon"}},
        {"https://example.com/second", %{}}
      ]

      wire =
        Message.build_response(180)
        |> Message.put_header(key, values)
        |> to_string()

      assert wire =~
               "#{name}: <https://example.com/first>;purpose=icon, <https://example.com/second>\r\n"

      assert {:ok, reparsed} = Message.parse(wire)
      assert reparsed.headers[key] == values
    end
  end

  test "Contact feature-tag parameters round-trip quoted" do
    raw =
      "REGISTER sip:ims.test SIP/2.0\r\n" <>
        "Via: SIP/2.0/UDP 1.2.3.4;branch=z9hG4bKx;received=2001:db8::1\r\n" <>
        "From: <sip:a@ims.test>;tag=1\r\nTo: <sip:a@ims.test>\r\n" <>
        "Call-ID: c\r\nCSeq: 1 REGISTER\r\nMax-Forwards: 70\r\n" <>
        "Contact: <sip:a@1.2.3.4>;+sip.instance=\"<urn:gsma:imei:1234>\";reg-id=1;" <>
        "+g.3gpp.smsip;+g.3gpp.icsi-ref=\"urn%3Aurn-7%3A3gpp-service.ims.icsi.mmtel\";video\r\n" <>
        "Content-Length: 0\r\n\r\n"

    {:ok, msg} = Message.parse(raw)
    wire = to_string(msg)

    assert wire =~ ~s(;+sip.instance="<urn:gsma:imei:1234>")
    assert wire =~ ~s(;+g.3gpp.icsi-ref="urn%3Aurn-7%3A3gpp-service.ims.icsi.mmtel")
    assert wire =~ ~r/;\+g\.3gpp\.smsip(;|\r\n)/
    assert wire =~ ~r/;video(;|\r\n)/
    assert wire =~ ";reg-id=1"
    assert wire =~ ";received=2001:db8::1"

    {:ok, reparsed} = Message.parse(wire)
    assert reparsed.headers.contact == msg.headers.contact
  end

  test "put headers" do
    response =
      Message.build_response(200)
      |> Message.put_new_header(:a, [%{value: 2}])
      |> Message.put_new_header(:a, [%{value: 99}])
      |> Message.put_header_front(:a, %{value: 1})
      |> Message.put_header_back(:a, %{value: 3})
      |> Message.put_new_lazy_header(:b, fn -> [%{value: 2}] end)

    assert Message.has_header?(response, :a) == true
    assert Message.has_header?(response, :b) == true
    assert Message.has_header?(response, :c) == false

    assert length(response.headers[:a]) == 3
    assert length(response.headers[:b]) == 1

    assert List.foldr(response.headers[:a], [], fn x, acc -> [x.value | acc] end) == [1, 2, 3]

    assert Enum.at(response.headers[:b], 0).value == 2
  end

  test "delete headers" do
    response =
      Message.build_response(200)
      |> Message.put_new_header(:a, [%{value: 2}])
      |> Message.put_header_front(:a, %{value: 1})
      |> Message.put_header_back(:a, %{value: 3})
      |> Message.put_new_header(:b, [%{value: 99}])

    r1 = response |> Message.delete_header(:a)
    assert Message.has_header?(r1, :a) == false

    r2 = response |> Message.delete_header_front(:a)
    assert List.first(r2.headers[:a]).value == 2

    r3 = response |> Message.delete_header_back(:a)
    assert List.last(r3.headers[:a]).value == 2

    r4 = response |> Message.drop_headers([:a, :b])
    assert map_size(r4.headers) == 0

    r5 =
      response
      |> Message.delete_header(:c)
      |> Message.delete_header_front(:d)
      |> Message.delete_header_back(:e)

    assert map_size(r5.headers) == 2

    r6 = response |> Message.drop_headers([:c, :d])
    assert map_size(r6.headers) == 2
  end

  test "fetch headers" do
    response =
      Message.build_response(200)
      |> Message.put_new_header(:a, [%{value: 2}])
      |> Message.put_header_front(:a, %{value: 1})
      |> Message.put_header_back(:a, %{value: 3})
      |> Message.put_header_back(:c, nil)

    {:ok, values} = Message.fetch_header(response, :a)

    assert List.foldr(values, [], fn x, acc -> [x.value | acc] end) ==
             [1, 2, 3]

    assert Message.fetch_header_front(response, :a) ==
             {:ok, %{value: 1}}

    assert Message.fetch_header_back(response, :a) ==
             {:ok, %{value: 3}}

    assert Message.fetch_header(response, :c) == {:ok, []}
    assert Message.fetch_header_front(response, :c) == {:ok, nil}
    assert Message.fetch_header_back(response, :c) == {:ok, nil}

    assert Message.fetch_header(response, :b) == :error
    assert Message.fetch_header_front(response, :b) == :error
    assert Message.fetch_header_back(response, :b) == :error
  end

  test "fetch! headers" do
    response =
      Message.build_response(200)
      |> Message.put_new_header(:a, [%{value: 2}])
      |> Message.put_header_front(:a, %{value: 1})
      |> Message.put_header_back(:a, %{value: 3})
      |> Message.put_header_back(:c, nil)

    values = Message.fetch_header!(response, :a)

    assert List.foldr(values, [], fn x, acc -> [x.value | acc] end) ==
             [1, 2, 3]

    assert Message.fetch_header_front!(response, :a) ==
             %{value: 1}

    assert Message.fetch_header_back!(response, :a) ==
             %{value: 3}

    assert Message.fetch_header!(response, :c) == []
    assert Message.fetch_header_front!(response, :c) == nil
    assert Message.fetch_header_back!(response, :c) == nil

    assert_raise(KeyError, fn -> Message.fetch_header!(response, :b) end)
    assert_raise(KeyError, fn -> Message.fetch_header_front!(response, :b) end)
    assert_raise(KeyError, fn -> Message.fetch_header_back!(response, :b) end)
  end

  test "get headers" do
    response =
      Message.build_response(200)
      |> Message.put_new_header(:a, [%{value: 2}])
      |> Message.put_header_front(:a, %{value: 1})
      |> Message.put_header_back(:a, %{value: 3})

    assert Message.get_header(response, :a)
           |> List.foldr([], fn x, acc -> [x.value | acc] end) == [1, 2, 3]

    assert Message.get_header_front(response, :a) == %{value: 1}
    assert Message.get_header_back(response, :a) == %{value: 3}

    assert Message.get_header(response, :b) == nil
    assert Message.get_header_front(response, :b) == nil
    assert Message.get_header_back(response, :b) == nil

    assert Message.get_header(response, :b, 99) == 99
    assert Message.get_header_front(response, :b, 99) == 99
    assert Message.get_header_back(response, :b, 99) == 99
  end

  test "update headers" do
    response =
      Message.build_response(200)
      |> Message.put_new_header(:a, [%{value: 2}])
      |> Message.put_header_front(:a, %{value: 1})
      |> Message.put_header_back(:a, %{value: 3})

    r1 =
      response
      |> Message.update_header(:a, [], fn values ->
        values |> List.foldr([], fn x, acc -> [%{x | value: x.value + 1} | acc] end)
      end)

    assert Message.get_header_front(r1, :a).value == 2
    assert Message.get_header_back(r1, :a).value == 4

    r2 = response |> Message.update_header_front(:a, nil, fn x -> %{x | value: 99} end)
    assert Message.get_header_front(r2, :a).value == 99

    r3 = response |> Message.update_header_back(:a, nil, fn x -> %{x | value: 99} end)
    assert Message.get_header_back(r3, :a).value == 99

    r4 = response |> Message.update_header(:b, [%{value: 99}], fn values -> values end)
    assert Message.get_header(r4, :b) == [%{value: 99}]

    r5 = response |> Message.update_header_front(:b, %{value: 99}, fn values -> values end)
    assert Message.get_header(r5, :b) == [%{value: 99}]

    r6 = response |> Message.update_header_back(:b, %{value: 99}, fn values -> values end)
    assert Message.get_header(r6, :b) == [%{value: 99}]
  end

  test "pop headers" do
    response =
      Message.build_response(200)
      |> Message.put_new_header(:a, [%{value: 2}])
      |> Message.put_header_front(:a, %{value: 1})
      |> Message.put_header_back(:a, %{value: 3})

    {values, r1} = Message.pop_header(response, :a)
    assert List.foldr(values, [], fn x, acc -> [x.value | acc] end) == [1, 2, 3]
    assert map_size(r1.headers) == 0

    {%{value: 1}, r2} = Message.pop_header_front(response, :a)
    assert length(Message.get_header(r2, :a)) == 2

    {%{value: 3}, r3} = Message.pop_header_back(response, :a)
    assert length(Message.get_header(r3, :a)) == 2

    {x1, r4} = Message.pop_header(response, :b, [%{value: 99}])
    assert x1 == [%{value: 99}]
    assert r4 == response

    {x2, r5} = Message.pop_header_front(response, :b, %{value: 99})
    assert x2 == %{value: 99}
    assert r5 == response

    {x3, r6} = Message.pop_header_back(response, :b, %{value: 99})
    assert x3 == %{value: 99}
    assert r6 == response
  end

  test "get and update headers" do
    response =
      Message.build_response(200)
      |> Message.put_new_header(:a, [%{value: 2}])
      |> Message.put_header_front(:a, %{value: 1})
      |> Message.put_header_back(:a, %{value: 3})

    {get, r1} =
      response
      |> Message.get_and_update_header(
        :a,
        fn current_values ->
          {current_values,
           List.foldr(current_values, [], fn x, acc ->
             [%{value: x.value + 1} | acc]
           end)}
        end
      )

    assert Message.get_header_front(r1, :a).value == 2
    assert Message.get_header_back(r1, :a).value == 4
    assert get == Message.get_header(response, :a)

    {_, r2} =
      response
      |> Message.get_and_update_header_front(
        :a,
        fn current_value ->
          {current_value, %{value: 99}}
        end
      )

    assert Message.get_header(r2, :a)
           |> List.foldr([], fn x, acc -> [x.value | acc] end) == [99, 2, 3]

    {_, r3} =
      response
      |> Message.get_and_update_header_back(
        :a,
        fn current_value ->
          {current_value, %{value: 99}}
        end
      )

    assert Message.get_header(r3, :a)
           |> List.foldr([], fn x, acc -> [x.value | acc] end) == [1, 2, 99]

    {_, r4} =
      response
      |> Message.get_and_update_header_front(
        :b,
        fn current_value ->
          {current_value, nil}
        end
      )

    assert Message.get_header(r4, :b)
           |> List.foldr([], fn x, acc -> [x.value | acc] end) == []

    {_, r5} =
      response
      |> Message.get_and_update_header_front(:a, fn _ -> :pop end)

    assert Message.get_header(r5, :a)
           |> List.foldr([], fn x, acc -> [x.value | acc] end) == [2, 3]
  end

  test "encoding via header" do
    req =
      """
      INVITE sip:5531999921578@85.90.232.52 SIP/2.0
      Via: SIP/2.0/UDP 192.168.65.17:5566;branch=z9hG4bKMD3xTURX0heu
      Via: SIP/2.0/STOMP D6wU5SvE.invalid;rport=5672;received=192.168.65.30;branch=z9hG4bKRtAc6V4VeIuR
      """
      |> Message.parse!()

    message =
      "INVITE sip:5531999921578@85.90.232.52 SIP/2.0\r\n" <>
        "Content-Length: 0\r\n" <>
        "Via: SIP/2.0/UDP 192.168.65.17:5566;branch=z9hG4bKMD3xTURX0heu, " <>
        "SIP/2.0/STOMP D6wU5SvE.invalid;rport=5672;received=192.168.65.30" <>
        ";branch=z9hG4bKRtAc6V4VeIuR\r\n" <>
        "\r\n"

    assert message == req |> to_string
  end

  test "encoding empty rport" do
    req =
      """
      INVITE sip:foo@bar.com SIP/2.0
      Via: SIP/2.0/UDP 205.205.74.6:5060;rport;branch=z9hG4bK-26320-1-0
      """
      |> Message.parse!()

    message =
      "INVITE sip:foo@bar.com SIP/2.0\r\n" <>
        "Content-Length: 0\r\n" <>
        "Via: SIP/2.0/UDP 205.205.74.6:5060;rport;branch=z9hG4bK-26320-1-0\r\n" <>
        "\r\n"

    assert message == req |> to_string
  end

  test "parse request with body" do
    raw_request = """
    INVITE sip:bob@biloxi.com SIP/2.0
    Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds

    v=0
    o=- 8789325071243167256 2 IN IP4 127.0.0.1
    """

    parsed_request = Message.parse!(raw_request)

    expected_body = """
    v=0
    o=- 8789325071243167256 2 IN IP4 127.0.0.1
    """

    assert parsed_request.body == expected_body
  end

  test "parse multiple Reason headers" do
    req =
      """
      CANCEL sip:bob@biloxi.com SIP/2.0
      Reason: X.int;reasoncode=0x0000030A;add-info=068C.0001.0001
      Reason: SIP;cause=200;text="Call Rejected By User"
      """
      |> Message.parse!()

    message =
      "CANCEL sip:bob@biloxi.com SIP/2.0\r\n" <>
        "Content-Length: 0\r\n" <>
        "Reason: X.int;reasoncode=0x0000030A;add-info=068C.0001.0001, " <>
        "SIP;text=\"Call Rejected By User\";cause=200\r\n" <>
        "\r\n"

    assert message == req |> to_string
  end

  describe "RAck header (RFC 3262 section 7.2, P5GM-3895)" do
    defp parse_rack(value) do
      Message.parse("PRACK sip:bob@biloxi.com SIP/2.0\r\nRAck: #{value}\r\n\r\n")
    end

    test "keeps the method of the acknowledged request" do
      assert {:ok, %{headers: %{rack: {9, "314 INVITE"}}}} = parse_rack("9 314 INVITE")
      assert {:ok, %{headers: %{rack: {9, "314 BYE"}}}} = parse_rack("9 314 BYE")
    end

    test "tolerates extra linear white space" do
      assert {:ok, %{headers: %{rack: {9, "314 INVITE"}}}} = parse_rack("9 \t 314   INVITE ")
    end

    test "rejects missing fields" do
      assert {:error, {:error, :missing_response_num}} = parse_rack("")
      assert {:error, {:error, :missing_cseq_num}} = parse_rack("9")
      assert {:error, {:error, :missing_method}} = parse_rack("9 314")
    end

    test "rejects non-numeric response-num and CSeq-num" do
      assert {:error, {:error, :invalid_response_num}} = parse_rack("x 314 INVITE")
      assert {:error, {:error, :invalid_response_num}} = parse_rack("-9 314 INVITE")
      assert {:error, {:error, :invalid_cseq_num}} = parse_rack("9 x INVITE")
      assert {:error, {:error, :invalid_cseq_num}} = parse_rack("9 +314 INVITE")
    end

    test "round-trips through parse and serialization" do
      rack =
        Message.build_request(:prack, "sip:bob@biloxi.com")
        |> Message.put_header(:rack, {9, "314 INVITE"})
        |> to_string()

      assert rack =~ "\r\nRAck: 9 314 INVITE\r\n"
      assert {:ok, %{headers: %{rack: {9, "314 INVITE"}}} = parsed} = Message.parse(rack)
      assert to_string(parsed) == rack
    end
  end

  describe "auth header quoting (RFC 3261 section 25.1)" do
    defp header_line(wire, name) do
      wire
      |> String.split("\r\n")
      |> Enum.find(&String.starts_with?(&1, name <> ": "))
    end

    defp auth_params(line) do
      [_name, _scheme, params] = String.split(line, " ", parts: 3)

      params
      |> String.split(",")
      |> MapSet.new()
    end

    @challenge %{
      "realm" => "ims.mnc001.mcc001.3gppnetwork.org",
      "domain" => "sip:ims.test sip:other.test",
      "nonce" => "L+8qJATjiDBcmaZrEG3BGaxDst0AjoAAQVEQa1b2yrc=",
      "opaque" => "J32zlCUOH4H7gg7WG6hluA",
      "algorithm" => "AKAv1-MD5",
      "stale" => "FALSE",
      "qop" => "auth"
    }

    @credentials %{
      "username" => "user@ims.test",
      "realm" => "ims.test",
      "nonce" => "abc",
      "uri" => "sip:ims.test",
      "response" => "6629fae49393a05397450978507c4ef1",
      "cnonce" => "0a4f113b",
      "opaque" => "5ccc069c403ebaf9f0171e9517f40e41",
      "algorithm" => "MD5",
      "qop" => "auth",
      "nc" => "00000001"
    }

    for {header, name} <- [www_authenticate: "WWW-Authenticate", proxy_authenticate: "Proxy-Authenticate"] do
      test "#{name} quotes qop and other quoted-string params" do
        wire =
          Message.build_response(401)
          |> Message.put_header(unquote(header), [{"Digest", @challenge}])
          |> to_string()

        line = header_line(wire, unquote(name))
        assert String.starts_with?(line, unquote(name) <> ": Digest ")

        assert auth_params(line) ==
                 MapSet.new([
                   ~s(realm="ims.mnc001.mcc001.3gppnetwork.org"),
                   ~s(domain="sip:ims.test sip:other.test"),
                   ~s(nonce="L+8qJATjiDBcmaZrEG3BGaxDst0AjoAAQVEQa1b2yrc="),
                   ~s(opaque="J32zlCUOH4H7gg7WG6hluA"),
                   "algorithm=AKAv1-MD5",
                   "stale=FALSE",
                   ~s(qop="auth")
                 ])
      end
    end

    for {header, name} <- [authorization: "Authorization", proxy_authorization: "Proxy-Authorization"] do
      test "#{name} keeps qop and nc as tokens" do
        wire =
          Message.build_request("REGISTER", "sip:ims.test")
          |> Message.put_header(unquote(header), [{"Digest", @credentials}])
          |> to_string()

        line = header_line(wire, unquote(name))
        assert String.starts_with?(line, unquote(name) <> ": Digest ")

        assert auth_params(line) ==
                 MapSet.new([
                   ~s(username="user@ims.test"),
                   ~s(realm="ims.test"),
                   ~s(nonce="abc"),
                   ~s(uri="sip:ims.test"),
                   ~s(response="6629fae49393a05397450978507c4ef1"),
                   ~s(cnonce="0a4f113b"),
                   ~s(opaque="5ccc069c403ebaf9f0171e9517f40e41"),
                   "algorithm=MD5",
                   "qop=auth",
                   "nc=00000001"
                 ])
      end
    end

    test "multiple qop values are a single quoted-string in a challenge" do
      wire =
        Message.build_response(401)
        |> Message.put_header(:www_authenticate, [
          {"Digest", %{"realm" => "r", "nonce" => "n", "qop" => "auth,auth-int"}}
        ])
        |> to_string()

      assert header_line(wire, "WWW-Authenticate") =~ ~s(qop="auth,auth-int")
    end

    test "parameter names are matched case-insensitively" do
      wire =
        Message.build_response(401)
        |> Message.put_header(:www_authenticate, [{"Digest", %{"QOP" => "auth"}}])
        |> to_string()

      assert header_line(wire, "WWW-Authenticate") == ~s(WWW-Authenticate: Digest QOP="auth")
    end

    test "unknown auth-params are quoted only when not a token" do
      wire =
        Message.build_response(401)
        |> Message.put_header(:www_authenticate, [
          {"Digest", %{"ck" => "00112233445566778899aabbccddeeff", "x-note" => ~s(a "b" \\ c)}}
        ])
        |> to_string()

      line = header_line(wire, "WWW-Authenticate")
      assert line =~ "ck=00112233445566778899aabbccddeeff"
      assert line =~ ~S(x-note="a \"b\" \\ c")

      {:ok, reparsed} = Message.parse(wire)

      assert [{"Digest", %{"x-note" => ~s(a "b" \\ c)}}] =
               reparsed.headers.www_authenticate
    end

    test "IMS 401 challenge round-trips with quoted qop" do
      raw =
        "SIP/2.0 401 Unauthorized\r\n" <>
          "Via: SIP/2.0/UDP 1.2.3.4;branch=z9hG4bKx\r\n" <>
          "From: <sip:a@ims.test>;tag=1\r\nTo: <sip:a@ims.test>;tag=2\r\n" <>
          "Call-ID: c\r\nCSeq: 1 REGISTER\r\n" <>
          "WWW-Authenticate: Digest algorithm=AKAv1-MD5," <>
          ~s(nonce="L+8qJATjiDBcmaZrEG3BGaxDst0AjoAAQVEQa1b2yrc=",) <>
          ~s(opaque="J32zlCUOH4H7gg7WG6hluA",qop=auth,) <>
          ~s(realm="ims.mnc001.mcc001.3gppnetwork.org"\r\n) <>
          "Content-Length: 0\r\n\r\n"

      {:ok, msg} = Message.parse(raw)
      wire = to_string(msg)
      line = header_line(wire, "WWW-Authenticate")

      assert line =~ ~s(qop="auth")
      assert line =~ ~s(realm="ims.mnc001.mcc001.3gppnetwork.org")
      assert line =~ "algorithm=AKAv1-MD5"
      refute line =~ "qop=auth"

      {:ok, reparsed} = Message.parse(wire)
      assert reparsed.headers.www_authenticate == msg.headers.www_authenticate
    end

    test "DigestAuth.make_response/4 emits a quoted qop" do
      request =
        Message.parse!(
          "REGISTER sip:ims.test SIP/2.0\r\n" <>
            "Via: SIP/2.0/UDP 1.2.3.4;branch=z9hG4bKx\r\n" <>
            "From: <sip:a@ims.test>;tag=1\r\nTo: <sip:a@ims.test>\r\n" <>
            "Call-ID: c\r\nCSeq: 1 REGISTER\r\nMax-Forwards: 70\r\n" <>
            "Content-Length: 0\r\n\r\n"
        )

      {:ok, response} = Sippet.DigestAuth.make_response(request, 401, "ims.test")

      line = response |> to_string() |> header_line("WWW-Authenticate")
      assert line =~ ~s(qop="auth")
      assert line =~ "algorithm=MD5"
    end
  end
end
