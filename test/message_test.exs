defmodule Sippet.Message.Test do
  use ExUnit.Case, async: true
  doctest Sippet.Message

  alias Sippet.Message, as: Message

  test "build request" do
    request = Message.build_request("REGISTER",
        "sip:registrar.biloxi.com")
    assert Message.request?(request)
  end

  test "build response" do
    response = Message.build_response(200, "OK")
    assert Message.response?(response)
  end

  test "put headers" do
    response = Message.build_response(200)
            |> Message.put_new_header(:a, [%{value: 2}])
            |> Message.put_new_header(:a, [%{value: 99}])
            |> Message.put_header_front(:a, %{value: 1})
            |> Message.put_header_back(:a, %{value: 3})
            |> Message.put_new_lazy_header(:b, fn() -> [%{value: 2}] end)

    assert Message.has_header?(response, :a) == true
    assert Message.has_header?(response, :b) == true
    assert Message.has_header?(response, :c) == false

    assert length(response.headers[:a]) == 3
    assert length(response.headers[:b]) == 1

    assert List.foldr(response.headers[:a], [],
        fn(x, acc) -> [x.value|acc] end) == [1, 2, 3]

    assert Enum.at(response.headers[:b], 0).value == 2
  end

  test "delete headers" do
    response = Message.build_response(200)
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

    r5 = response
         |> Message.delete_header(:c)
         |> Message.delete_header_front(:d)
         |> Message.delete_header_back(:e)
    assert map_size(r5.headers) == 2

    r6 = response |> Message.drop_headers([:c, :d])
    assert map_size(r6.headers) == 2
  end

  test "fetch headers" do
    response = Message.build_response(200)
            |> Message.put_new_header(:a, [%{value: 2}])
            |> Message.put_header_front(:a, %{value: 1})
            |> Message.put_header_back(:a, %{value: 3})
            |> Message.put_header_back(:c, nil)

    {:ok, values} = Message.fetch_header(response, :a)
    assert List.foldr(values, [], fn(x, acc) -> [x.value|acc] end)
        == [1, 2, 3]
    assert Message.fetch_header_front(response, :a)
        == {:ok, %{value: 1}}
    assert Message.fetch_header_back(response, :a)
        == {:ok, %{value: 3}}

    assert Message.fetch_header(response, :c) == {:ok, []}
    assert Message.fetch_header_front(response, :c) == {:ok, nil}
    assert Message.fetch_header_back(response, :c) == {:ok, nil}

    assert Message.fetch_header(response, :b) == :error
    assert Message.fetch_header_front(response, :b) == :error
    assert Message.fetch_header_back(response, :b) == :error
  end

  test "fetch! headers" do
    response = Message.build_response(200)
            |> Message.put_new_header(:a, [%{value: 2}])
            |> Message.put_header_front(:a, %{value: 1})
            |> Message.put_header_back(:a, %{value: 3})
            |> Message.put_header_back(:c, nil)

    values = Message.fetch_header!(response, :a)
    assert List.foldr(values, [], fn(x, acc) -> [x.value|acc] end)
        == [1, 2, 3]
    assert Message.fetch_header_front!(response, :a)
        == %{value: 1}
    assert Message.fetch_header_back!(response, :a)
        == %{value: 3}

    assert Message.fetch_header!(response, :c) == []
    assert Message.fetch_header_front!(response, :c) == nil
    assert Message.fetch_header_back!(response, :c) == nil

    assert_raise(KeyError, fn -> Message.fetch_header!(response, :b) end)
    assert_raise(KeyError, fn -> Message.fetch_header_front!(response, :b) end)
    assert_raise(KeyError, fn -> Message.fetch_header_back!(response, :b) end)
  end

  test "get headers" do
    response = Message.build_response(200)
            |> Message.put_new_header(:a, [%{value: 2}])
            |> Message.put_header_front(:a, %{value: 1})
            |> Message.put_header_back(:a, %{value: 3})

    assert Message.get_header(response, :a)
           |> List.foldr([], fn(x, acc) -> [x.value|acc] end) == [1, 2, 3]

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
    response = Message.build_response(200)
            |> Message.put_new_header(:a, [%{value: 2}])
            |> Message.put_header_front(:a, %{value: 1})
            |> Message.put_header_back(:a, %{value: 3})

    r1 = response |> Message.update_header(:a, [],
        fn(values) ->
            values |> List.foldr([], fn(x, acc) -> [%{x | value: x.value + 1} | acc] end)
        end)
    assert Message.get_header_front(r1, :a).value == 2
    assert Message.get_header_back(r1, :a).value == 4

    r2 = response |> Message.update_header_front(:a, nil,
        fn(x) -> %{x | value: 99} end)
    assert Message.get_header_front(r2, :a).value == 99

    r3 = response |> Message.update_header_back(:a, nil,
        fn(x) -> %{x | value: 99} end)
    assert Message.get_header_back(r3, :a).value == 99

    r4 = response |> Message.update_header(:b, [%{value: 99}],
        fn(values) -> values end)
    assert Message.get_header(r4, :b) == [%{value: 99}]

    r5 = response |> Message.update_header_front(:b, %{value: 99},
        fn(values) -> values end)
    assert Message.get_header(r5, :b) == [%{value: 99}]

    r6 = response |> Message.update_header_back(:b, %{value: 99},
        fn(values) -> values end)
    assert Message.get_header(r6, :b) == [%{value: 99}]
  end

  test "pop headers" do
    response = Message.build_response(200)
            |> Message.put_new_header(:a, [%{value: 2}])
            |> Message.put_header_front(:a, %{value: 1})
            |> Message.put_header_back(:a, %{value: 3})

    {values, r1} = Message.pop_header(response, :a)
    assert List.foldr(values, [], fn(x, acc) -> [x.value|acc] end) == [1, 2, 3]
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
    response = Message.build_response(200)
            |> Message.put_new_header(:a, [%{value: 2}])
            |> Message.put_header_front(:a, %{value: 1})
            |> Message.put_header_back(:a, %{value: 3})

    {get, r1} = response
                |> Message.get_and_update_header(:a,
                    fn(current_values) ->
                        {current_values, List.foldr(current_values, [],
                            fn(x, acc) ->
                                [%{value: x.value + 1} | acc]
                            end)}
                    end)
    assert Message.get_header_front(r1, :a).value == 2
    assert Message.get_header_back(r1, :a).value == 4
    assert get == Message.get_header(response, :a)

    {_, r2} = response
              |> Message.get_and_update_header_front(:a,
                  fn(current_value) ->
                      {current_value, %{value: 99}}
                  end)
    assert Message.get_header(r2, :a)
           |> List.foldr([], fn(x, acc) -> [x.value|acc] end) == [99, 2, 3]

    {_, r3} = response
              |> Message.get_and_update_header_back(:a,
                  fn(current_value) ->
                      {current_value, %{value: 99}}
                  end)
    assert Message.get_header(r3, :a)
           |> List.foldr([], fn(x, acc) -> [x.value|acc] end) == [1, 2, 99]

    {_, r4} = response
              |> Message.get_and_update_header_front(:b,
                  fn(current_value) ->
                      {current_value, nil}
                  end)
    assert Message.get_header(r4, :b)
           |> List.foldr([], fn(x, acc) -> [x.value|acc] end) == []

    {_, r5} = response
              |> Message.get_and_update_header_front(:a, fn(_) -> :pop end)
    assert Message.get_header(r5, :a)
           |> List.foldr([], fn(x, acc) -> [x.value|acc] end) == [2, 3]

  end

  test "encoding via header" do
    req =
      """
      INVITE sip:5531999921578@85.90.232.52 SIP/2.0
      Via: SIP/2.0/UDP 192.168.65.17:5566;branch=z9hG4bKMD3xTURX0heu
      Via: SIP/2.0/STOMP D6wU5SvE.invalid;rport=5672;received=192.168.65.30;branch=z9hG4bKRtAc6V4VeIuR
      """ |> Message.parse!()

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
      """ |> Message.parse!()

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
      """ |> Message.parse!()

    message =
      "CANCEL sip:bob@biloxi.com SIP/2.0\r\n" <>
      "Content-Length: 0\r\n" <>
      "Reason: X.int;reasoncode=0x0000030A;add-info=068C.0001.0001, " <>
      "SIP;text=\"Call Rejected By User\";cause=200\r\n" <>
        "\r\n"

    assert message == req |> to_string
  end
end
