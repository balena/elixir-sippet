defmodule Sippet.DigestAuth do
  @moduledoc """
  Implements the Digest authentication protocol.
  """

  alias Sippet.Message
  alias Sippet.Message.{RequestLine, StatusLine}

  @type password :: binary

  @type username :: binary

  @type realm :: binary

  @type reason :: term

  @type options :: [option]

  @type option :: {:cnonce, binary} | {:nc, binary}

  @doc """
  Adds an `Authorization` or `Proxy-Authorization` header for a request after
  receiving a 401 or 407 response. `CSeq` must be updated after calling this
  function.

  `incoming_response` must be an incoming 401/407 response containing a single
  challenge header (either Proxy-Authenticate or WWW-Authenticate) and
  `outgoing_request` is the last request sent to the server. The passed
  function receives the realm and should return `{:ok, username, password}` or
  `{:error, reason}`.
  """
  @spec make_request(
          outgoing_request :: Message.request(),
          incoming_response :: Message.response(),
          (realm -> {:ok, username, password} | {:error, reason}),
          options
        ) :: {:ok, Message.request()} | {:error, reason}
  def make_request(
        %Message{start_line: %RequestLine{method: req_method, request_uri: req_uri}} =
          outgoing_request,
        %Message{start_line: %StatusLine{}} = incoming_response,
        authenticate,
        options \\ []
      ) do
    with {:ok, realm, resp_header, resp_params} <-
           validate_challenge(outgoing_request, incoming_response),
         {:ok, username, password} <- authenticate.(realm),
         {:ok, req_parameters} <-
           do_make_request(req_uri, req_method, resp_params, username, password, options) do
      req_header =
        case resp_header do
          :www_authenticate -> :authorization
          :proxy_authenticate -> :proxy_authorization
        end

      new_req =
        outgoing_request
        |> Message.put_header_back(req_header, {"Digest", req_parameters})

      {:ok, new_req}
    else
      error -> error
    end
  end

  defp validate_challenge(outgoing_request, incoming_response) do
    req_nonces =
      [:authorization, :proxy_authorization]
      |> Enum.flat_map(fn header ->
        outgoing_request
        |> Message.get_header(header, [])
      end)
      |> Enum.flat_map(fn {scheme, parameters} ->
        with "digest" <- String.downcase(scheme),
             %{"nonce" => nonce} <- parameters do
          [nonce]
        else
          _otherwise -> []
        end
      end)

    result =
      [:www_authenticate, :proxy_authenticate]
      |> Enum.find_value(fn header ->
        with [{scheme, %{"nonce" => nonce, "realm" => realm} = params}] <-
               Message.get_header(incoming_response, header),
             "digest" <- String.downcase(scheme) do
          {nonce, realm, header, params}
        else
          _otherwise -> false
        end
      end)

    case result do
      {resp_nonce, resp_realm, resp_header, resp_params} ->
        if resp_nonce in req_nonces do
          {:error, :unknown_nonce}
        else
          {:ok, resp_realm, resp_header, resp_params}
        end

      nil ->
        {:error, :invalid_auth_header}
    end
  end

  defp do_make_request(
         req_uri,
         req_method,
         %{"nonce" => nonce, "realm" => realm} = resp_params,
         username,
         password,
         options
       ) do
    qop =
      resp_params
      |> Map.get("qop", "")
      |> String.split(",", trim: true)

    algorithm =
      resp_params
      |> Map.get("algorithm", "MD5")
      |> String.upcase()

    if algorithm == "MD5" and (qop == [] or "auth" in qop) do
      cnonce =
        options
        |> Keyword.get_lazy(:cnonce, &create_cnonce/0)

      nc =
        options
        |> Keyword.get(:nc, 1)

      nc_hex = :io_lib.format("~8.16.0B", [nc]) |> to_string()

      ha1 = make_ha1(username, password, realm)

      method =
        case req_method do
          :ack -> :invite
          method -> method
        end

      resp = make_auth_response(qop, method, req_uri, ha1, nonce, cnonce, nc_hex)

      req_params = %{
        "username" => username,
        "realm" => realm,
        "nonce" => nonce,
        "uri" => req_uri |> to_string(),
        "response" => resp,
      }

      req_params =
        if resp_params["algorithm"] == nil do
          req_params
        else
          req_params
          |> Map.put("algorithm", "MD5")
        end

      req_params =
        if qop == [] do
          req_params
        else
          req_params
          |> Map.put("qop", "auth")
          |> Map.put("cnonce", cnonce)
          |> Map.put("nc", nc_hex)
        end

      req_params =
        case resp_params do
          %{"opaque" => opaque} ->
            req_params
            |> Map.put("opaque", opaque)

          _otherwise ->
            req_params
        end

      {:ok, req_params}
    else
      {:error, :invalid_auth_header}
    end
  end

  defp make_ha1(username, password, realm),
    do: :crypto.hash(:md5, "#{username}:#{realm}:#{password}")

  defp make_auth_response(qop, method, uri, ha1, nonce, cnonce, nc) do
    ha1_hex =
      ha1
      |> Base.encode16(case: :lower)

    method =
      method
      |> to_string()
      |> String.upcase()

    ha2_base = "#{method}:#{uri |> to_string()}"

    ha2 =
      :crypto.hash(:md5, ha2_base)
      |> Base.encode16(case: :lower)

    cond do
      qop == [] ->
        :crypto.hash(:md5, "#{ha1_hex}:#{nonce}:#{ha2}")
        |> Base.encode16(case: :lower)

      "auth" in qop ->
        :crypto.hash(:md5, "#{ha1_hex}:#{nonce}:#{nc}:#{cnonce}:auth:#{ha2}")
        |> Base.encode16(case: :lower)
    end
  end

  defp create_cnonce(), do: do_random_string(256)

  defp do_random_string(length) do
    round(Float.ceil(length / 8))
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
