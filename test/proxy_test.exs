defmodule Sippet.Proxy.Test do
  use ExUnit.Case, async: true

  alias Sippet.Message, as: Message
  alias Sippet.URI, as: URI
  alias Sippet.Proxy, as: Proxy

  import Mock

  test "add record route" do
    request = Message.build_request(:register,
        "sip:registrar.biloxi.com")

    uri1 = URI.parse!("sip:pc33.biloxi.com")
    request1 = Proxy.add_record_route(request, uri1)

    assert {_, %URI{host: "pc33.biloxi.com", parameters: ";lr"}, _}
           |> match?(hd(request1.headers.record_route))

    uri2 = URI.parse!("sip:pc22.biloxi.com;lr")
    request2 = Proxy.add_record_route(request1, uri2)

    assert {_, %URI{host: "pc22.biloxi.com", parameters: ";lr"}, _}
           |> match?(hd(request2.headers.record_route))

  end

  test "add via" do
    request = Message.build_request(:register,
        "sip:registrar.biloxi.com")

    request1 = Proxy.add_via(request, :udp, "pc33.atlanta.com", 5060)

    {{2, 0}, :udp, {"pc33.atlanta.com", 5060}, %{"branch" => branch}} =
      hd(request1.headers.via)

    assert branch |> String.starts_with?("z9hG4bK")

    # if the user creates a branch by himself, and it starts with the magic
    # cookie, the branch will be copied, otherwise the magic cookie will be
    # added to the branch parameter.
    request2 = Proxy.add_via(request1, :udp, "pc22.atlanta.com", 5060,
                             "someWeirdBranch")

    {{2, 0}, :udp, {"pc22.atlanta.com", 5060}, %{"branch" => branch}} =
      hd(request2.headers.via)

    assert branch == "z9hG4bKsomeWeirdBranch"

    request3 = Proxy.add_via(request1, :udp, "pc11.atlanta.com", 5060,
                             "z9hG4bKFooBar")

    {{2, 0}, :udp, {"pc11.atlanta.com", 5060}, %{"branch" => branch}} =
      hd(request3.headers.via)

    assert branch == "z9hG4bKFooBar"
  end

  test "derive branch" do
    branch = "z9hG4bKasdfgh"

    # the derived branch is calculated using RIPEMD-160 HMAC.
    derived_branch =
      Sippet.Message.magic_cookie() <>
        (:crypto.hmac(:ripemd160, "sippet", branch)
         |> Base.url_encode64(padding: false))

    ack =
      Message.build_request(:ack, "sip:alice@biloxi.com")
      |> Message.put_header(:via, [
        {{2, 0}, :udp, {"10.10.1.1", 5060}, %{"branch" => branch}}
      ])

    assert derived_branch == Proxy.derive_branch(ack)
  end

  test "derive branch, RFC 2543" do
    branch = "asdfgh"

    input =
      ["sip:alice@biloxi.com", "udp", "10.10.1.1", "5060",
       "foo@bar", "qwerty", "zxcvb", "100", ["branch", branch]]

    # the derived branch is calculated using RIPEMD-160 HMAC.
    derived_branch =
      Sippet.Message.magic_cookie() <>
        (:crypto.hmac(:ripemd160, "sippet", input)
         |> Base.url_encode64(padding: false))

    ack =
      Message.build_request(:ack, "sip:alice@biloxi.com")
      |> Message.put_header(:via, [
        {{2, 0}, :udp, {"10.10.1.1", 5060}, %{"branch" => branch}}
      ])
      |> Message.put_header(:cseq, {100, :ack})
      |> Message.put_header(:call_id, "foo@bar")
      |> Message.put_header(:from, {"", URI.parse!("sip:bob@biloxi.com"),
                                    %{"tag" => "qwerty"}})
      |> Message.put_header(:to, {"", URI.parse!("sip:alice@biloxi.com"),
                                  %{"tag" => "zxcvb"}})

    assert derived_branch == Proxy.derive_branch(ack)
  end

  test "forward request" do
    # the header Max-Forwards should be added if it does not exist before
    # forwarding the request, otherwise the value should be subtracted.
    with_mock Sippet.Transactions,
        [send_request: fn _ -> {:ok, "abcd"} end] do
      request = :invite |> Message.build_request("sip:alice@biloxi.com")

      {:ok, "abcd", modified_request} = Proxy.forward_request(request)

      assert modified_request ==
        request
        |> Message.put_header(:max_forwards, 70)

      assert called Sippet.Transactions.send_request(:_)
    end

    with_mock Sippet.Transactions,
        [send_request: fn _ -> :ok end] do
      request =
        :invite
        |> Message.build_request("sip:alice@biloxi.com")
        |> Message.put_header(:max_forwards, 34)

      :ok = Proxy.forward_request(request)

      assert called Sippet.Transactions.send_request(
        request |> Message.put_header(:max_forwards, 33))
    end

    with_mock Sippet.Transactions,
        [send_request: fn _ -> :ok end] do
      request =
        :invite
        |> Message.build_request("sip:alice@biloxi.com")
        |> Message.put_header(:max_forwards, 0)

      assert_raise ArgumentError, fn -> Proxy.forward_request(request) end
    end

    with_mock Sippet.Transactions,
        [send_request: fn _ -> :ok end] do
      request = :invite |> Message.build_request("sip:alice@biloxi.com")

      request_to = URI.parse!("sip:bob@biloxi.com")
      :ok = Proxy.forward_request(request, request_to)

      message2 = %{request | start_line: %{request.start_line | request_uri: request_to}}
      assert called Sippet.Transactions.send_request(message2)
    end
  end
end
