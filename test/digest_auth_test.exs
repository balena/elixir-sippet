defmodule Sippet.DigestAuth.Test do
  use ExUnit.Case

  alias Sippet.{DigestAuth, Message}

  defp respond_to_challenge(resp_params, method, request_uri, body, cnonce) do
    outgoing_request =
      Message.build_request(method, request_uri)
      |> Map.put(:body, body)

    incoming_response =
      Message.build_response(401)
      |> Map.put(:headers, %{www_authenticate: [{"Digest", resp_params}]})

    {:ok, new_req} =
      DigestAuth.make_request(
        outgoing_request,
        incoming_response,
        fn _realm ->
          {:ok, "bob", "zanzibar"}
        end,
        cnonce: cnonce
      )

    [{"Digest", req_params}] = new_req.headers.authorization

    req_params
  end

  test "algorithm and qop not specified" do
    assert respond_to_challenge(
             %{
               "realm" => "biloxi.com",
               "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
               "opaque" => "5ccc069c403ebaf9f0171e9517f40e41"
             },
             :invite,
             "sip:bob@biloxi.com",
             "",
             "0a4f113b"
           ) == %{
             "username" => "bob",
             "realm" => "biloxi.com",
             "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
             "uri" => "sip:bob@biloxi.com",
             "response" => "bf57e4e0d0bffc0fbaedce64d59add5e",
             "opaque" => "5ccc069c403ebaf9f0171e9517f40e41"
           }
  end

  test "auth and algorithm unspecified" do
    assert respond_to_challenge(
             %{
               "qop" => "auth",
               "realm" => "biloxi.com",
               "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
               "opaque" => "5ccc069c403ebaf9f0171e9517f40e41"
             },
             :invite,
             "sip:bob@biloxi.com",
             "",
             "0a4f113b"
           ) == %{
             "username" => "bob",
             "realm" => "biloxi.com",
             "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
             "uri" => "sip:bob@biloxi.com",
             "response" => "89eb0059246c02b2f6ee02c7961d5ea3",
             "opaque" => "5ccc069c403ebaf9f0171e9517f40e41",
             "qop" => "auth",
             "nc" => "00000001",
             "cnonce" => "0a4f113b"
           }
  end

  test "auth and MD5" do
    assert respond_to_challenge(
             %{
               "qop" => "auth",
               "realm" => "biloxi.com",
               "algorithm" => "MD5",
               "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
               "opaque" => "5ccc069c403ebaf9f0171e9517f40e41"
             },
             :invite,
             "sip:bob@biloxi.com",
             "",
             "0a4f113b"
           ) == %{
             "username" => "bob",
             "realm" => "biloxi.com",
             "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
             "uri" => "sip:bob@biloxi.com",
             "response" => "89eb0059246c02b2f6ee02c7961d5ea3",
             "opaque" => "5ccc069c403ebaf9f0171e9517f40e41",
             "algorithm" => "MD5",
             "qop" => "auth",
             "nc" => "00000001",
             "cnonce" => "0a4f113b"
           }
  end

  test "auth and MD5-sess" do
    assert respond_to_challenge(
             %{
               "qop" => "auth",
               "realm" => "biloxi.com",
               "algorithm" => "MD5-sess",
               "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
               "opaque" => "5ccc069c403ebaf9f0171e9517f40e41"
             },
             :invite,
             "sip:bob@biloxi.com",
             "",
             "0a4f113b"
           ) == %{
             "username" => "bob",
             "realm" => "biloxi.com",
             "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
             "uri" => "sip:bob@biloxi.com",
             "response" => "e4e4ea61d186d07a92c9e1f6919902e9",
             "opaque" => "5ccc069c403ebaf9f0171e9517f40e41",
             "algorithm" => "MD5-sess",
             "qop" => "auth",
             "nc" => "00000001",
             "cnonce" => "0a4f113b"
           }
  end

  test "auth-int and MD5" do
    assert respond_to_challenge(
             %{
               "qop" => "auth-int",
               "realm" => "biloxi.com",
               "algorithm" => "MD5",
               "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
               "opaque" => "5ccc069c403ebaf9f0171e9517f40e41"
             },
             :invite,
             "sip:bob@biloxi.com",
             "v=0\r\n" <>
               "o=bob 2890844526 2890844526 IN IP4 media.biloxi.com\r\n" <>
               "s=-\r\n" <>
               "c=IN IP4 media.biloxi.com\r\n" <>
               "t=0 0\r\n" <>
               "m=audio 49170 RTP/AVP 0\r\n" <>
               "a=rtpmap:0 PCMU/8000\r\n" <>
               "m=video 51372 RTP/AVP 31\r\n" <>
               "a=rtpmap:31 H261/90000\r\n" <>
               "m=video 53000 RTP/AVP 32\r\n" <>
               "a=rtpmap:32 MPV/90000\r\n",
             "0a4f113b"
           ) == %{
             "username" => "bob",
             "realm" => "biloxi.com",
             "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
             "uri" => "sip:bob@biloxi.com",
             "response" => "bdbeebb2da6adb6bca02599c2239e192",
             "opaque" => "5ccc069c403ebaf9f0171e9517f40e41",
             "algorithm" => "MD5",
             "qop" => "auth-int",
             "nc" => "00000001",
             "cnonce" => "0a4f113b"
           }
  end

  test "auth-int and MD5-sess" do
    assert respond_to_challenge(
             %{
               "qop" => "auth-int",
               "realm" => "biloxi.com",
               "algorithm" => "MD5-sess",
               "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
               "opaque" => "5ccc069c403ebaf9f0171e9517f40e41"
             },
             :invite,
             "sip:bob@biloxi.com",
             "v=0\r\n" <>
               "o=bob 2890844526 2890844526 IN IP4 media.biloxi.com\r\n" <>
               "s=-\r\n" <>
               "c=IN IP4 media.biloxi.com\r\n" <>
               "t=0 0\r\n" <>
               "m=audio 49170 RTP/AVP 0\r\n" <>
               "a=rtpmap:0 PCMU/8000\r\n" <>
               "m=video 51372 RTP/AVP 31\r\n" <>
               "a=rtpmap:31 H261/90000\r\n" <>
               "m=video 53000 RTP/AVP 32\r\n" <>
               "a=rtpmap:32 MPV/90000\r\n",
             "0a4f113b"
           ) == %{
             "username" => "bob",
             "realm" => "biloxi.com",
             "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
             "uri" => "sip:bob@biloxi.com",
             "response" => "91984da2d8663716e91554859c22ca70",
             "opaque" => "5ccc069c403ebaf9f0171e9517f40e41",
             "algorithm" => "MD5-sess",
             "qop" => "auth-int",
             "nc" => "00000001",
             "cnonce" => "0a4f113b"
           }
  end
end
