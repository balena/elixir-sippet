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

  @type req_options :: [req_option]

  @type req_option :: {:cnonce, binary} | {:nc, binary}

  @type resp_options :: [resp_option]

  @type resp_option :: {:nonce, binary} | {:opaque, binary}

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
          req_options
        ) :: {:ok, Message.request()} | {:error, reason}
  def make_request(
        %Message{start_line: %RequestLine{method: req_method, request_uri: req_uri}, body: body} =
          outgoing_request,
        %Message{start_line: %StatusLine{}} = incoming_response,
        authenticate,
        options \\ []
      ) do
    with {:ok, realm, resp_header, resp_params} <-
           validate_challenge(outgoing_request, incoming_response),
         {:ok, username, password} <- authenticate.(realm),
         {:ok, req_parameters} <-
           do_make_request(req_uri, req_method, resp_params, username, password, body, options) do
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
         body,
         options
       ) do
    # Digest authentication is specified in RFC 2617.
    # The expanded derivations are listed in the tables below.
    #
    # +==========+==========+==========================================+
    # |    qop   |algorithm |               response                   |
    # +==========+==========+==========================================+
    # |    ?     |  ?, md5, | MD5(MD5(A1):nonce:MD5(A2))               |
    # |          | md5-sess |                                          |
    # +--------- +----------+------------------------------------------+
    # |   auth,  |  ?, md5, | MD5(MD5(A1):nonce:nc:cnonce:qop:MD5(A2)) |
    # | auth-int | md5-sess |                                          |
    # +==========+==========+==========================================+
    # |    qop   |algorithm |                  A1                      |
    # +==========+==========+==========================================+
    # |          | ?, md5   | user:realm:password                      |
    # +----------+----------+------------------------------------------+
    # |          | md5-sess | MD5(user:realm:password):nonce:cnonce    |
    # +==========+==========+==========================================+
    # |    qop   |algorithm |                  A2                      |
    # +==========+==========+==========================================+
    # |  ?, auth |          | req-method:req-uri                       |
    # +----------+----------+------------------------------------------+
    # | auth-int |          | req-method:req-uri:MD5(req-entity-body)  |
    # +=====================+==========================================+

    qop =
      resp_params
      |> Map.get("qop", "")
      |> String.split(",", trim: true)

    algorithm =
      resp_params
      |> Map.get("algorithm", "md5")
      |> String.downcase()

    cnonce =
      options
      |> Keyword.get_lazy(:cnonce, &create_cnonce/0)

    nc =
      options
      |> Keyword.get(:nc, 1)

    nc_hex = :io_lib.format("~8.16.0B", [nc]) |> to_string()

    ha1 =
      :crypto.hash(:md5, "#{username}:#{realm}:#{password}")
      |> Base.encode16(case: :lower)

    ha1 =
      if algorithm == "md5-sess" do
        :crypto.hash(:md5, ha1 <> ":#{nonce}:#{cnonce}")
        |> Base.encode16(case: :lower)
      else
        ha1
      end

    method =
      case req_method do
        :ack -> :invite
        method -> method
      end

    method =
      method
      |> to_string()
      |> String.upcase()

    a2 = "#{method}:#{req_uri |> to_string()}"

    a2 =
      if "auth-int" in qop do
        body_hash =
          :crypto.hash(:md5, body)
          |> Base.encode16(case: :lower)

        a2 <> ":#{body_hash}"
      else
        a2
      end

    ha2 =
      :crypto.hash(:md5, a2)
      |> Base.encode16(case: :lower)

    nc_part =
      if qop == [] do
        ""
      else
        "#{nc_hex}:#{cnonce}:#{qop_to_string(qop)}:"
      end

    resp =
      :crypto.hash(:md5, "#{ha1}:#{nonce}:#{nc_part}#{ha2}")
      |> Base.encode16(case: :lower)

    req_params = %{
      "username" => username,
      "realm" => realm,
      "nonce" => nonce,
      "uri" => req_uri |> to_string(),
      "response" => resp
    }

    req_params =
      if resp_params["algorithm"] == nil do
        req_params
      else
        req_params
        |> Map.put("algorithm", resp_params["algorithm"])
      end

    req_params =
      if qop == [] do
        req_params
      else
        req_params
        |> Map.put("qop", qop_to_string(qop))
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
  end

  defp qop_to_string(qop) do
    if "auth-int" in qop do
      "auth-int"
    else
      "auth"
    end
  end

  defp create_cnonce(), do: do_random_string(256)

  defp create_nonce(), do: do_random_string(256)

  defp create_opaque(), do: do_random_string(256)

  defp do_random_string(length) do
    round(Float.ceil(length / 8))
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates a response containing `WWW-Authenticate` or `Proxy-Authenticate`
  header for an incoming request. Use this function to answer to a request with
  a 401 or 407 response.

  A new `nonce' will be generated to be used by the client in its response,
  but will expire after the time configured indicated in `nonce_timeout'.
  """
  @spec make_response(
          incoming_request :: Message.request(),
          status :: 401 | 407,
          realm,
          resp_options
        ) :: {:ok, Message.response()}
  def make_response(
        %Message{start_line: %RequestLine{}} = incoming_request,
        status,
        realm,
        options \\ []
      )
      when is_binary(realm) and is_list(options) and status in [401, 407] do
    nonce =
      options
      |> Keyword.get_lazy(:nonce, &create_nonce/0)

    opaque =
      options
      |> Keyword.get_lazy(:opaque, &create_opaque/0)

    algorithm =
      options
      |> Keyword.get(:algorithm, "MD5")

    qop =
      options
      |> Keyword.get(:qop, "auth")

    resp =
      incoming_request
      |> Message.to_response(status)
      |> Message.put_header(status_to_header(status), [
        {"Digest",
         %{
           "realm" => realm,
           "nonce" => nonce,
           "algorithm" => algorithm,
           "qop" => qop,
           "opaque" => opaque
         }}
      ])

    {:ok, resp}
  end

  defp status_to_header(401), do: :www_authenticate
  defp status_to_header(407), do: :proxy_authenticate
end
