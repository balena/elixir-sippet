defmodule Sippet.Message do
  @moduledoc """
  Message primitive for composing SIP messages.
  Build a SIP message with the `Sippet.Message` struct.

      request =
        Sippet.Message.build_request("INVITE", "sip:joe@example.com")
        |> Sippet.Message.put_header(:to,
            {"", Sippet.URI.parse!("sip:joe@example.com"), %{}})
        ...
  """

  @behaviour Access

  alias Sippet.URI, as: URI
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  defstruct start_line: nil,
            headers: %{},
            body: nil,
            target: nil

  @type uri :: URI.t()

  @type method :: atom | binary

  @type header :: atom | binary

  @type protocol :: atom | binary

  @type token :: binary

  @type params :: %{binary => binary}

  @type token_params ::
          {token :: binary, params}

  @type type_subtype_params ::
          {{type :: binary, subtype :: binary}, params}

  @type uri_params ::
          {display_name :: binary, uri :: URI.t(), params}

  @type name_uri_params ::
          {display_name :: binary, uri :: URI.t(), params}

  @type auth_params ::
          {scheme :: binary, params}

  @type via_value ::
          {{major :: integer, minor :: integer}, protocol, {host :: binary, port :: integer},
           params}

  @type headers :: %{
          optional(:accept) => [type_subtype_params, ...],
          optional(:accept_encoding) => [token_params, ...],
          optional(:accept_language) => [token_params, ...],
          optional(:alert_info) => [uri_params, ...],
          optional(:allow) => [token, ...],
          optional(:authentication_info) => params,
          optional(:authorization) => [auth_params, ...],
          required(:call_id) => token,
          optional(:call_info) => [uri_params, ...],
          optional(:contact) => <<_::1>> | [name_uri_params, ...],
          optional(:content_disposition) => token_params,
          optional(:content_encoding) => [token, ...],
          optional(:content_language) => [token, ...],
          optional(:content_length) => integer,
          optional(:content_type) => type_subtype_params,
          required(:cseq) => {integer, method},
          optional(:date) => NaiveDateTime.t(),
          optional(:error_info) => [uri_params, ...],
          optional(:expires) => integer,
          required(:from) => name_uri_params,
          optional(:in_reply_to) => [token, ...],
          required(:max_forwards) => integer,
          optional(:mime_version) => {major :: integer, minor :: integer},
          optional(:min_expires) => integer,
          optional(:organization) => binary,
          optional(:priority) => token,
          optional(:proxy_authenticate) => [auth_params, ...],
          optional(:proxy_authorization) => [auth_params, ...],
          optional(:proxy_require) => [token, ...],
          optional(:reason) => {binary, params},
          optional(:record_route) => [name_uri_params, ...],
          optional(:reply_to) => name_uri_params,
          optional(:require) => [token, ...],
          optional(:retry_after) => {integer, binary, params},
          optional(:route) => [name_uri_params, ...],
          optional(:server) => binary,
          optional(:subject) => binary,
          optional(:supported) => [token, ...],
          optional(:timestamp) => {timestamp :: float, delay :: float},
          required(:to) => name_uri_params,
          optional(:unsupported) => [token, ...],
          optional(:user_agent) => binary,
          required(:via) => [via_value, ...],
          optional(:warning) => [{integer, agent :: binary, binary}, ...],
          optional(:www_authenticate) => [auth_params, ...],
          optional(binary) => [binary, ...]
        }

  @type single_value ::
          binary
          | integer
          | {sequence :: integer, method}
          | {major :: integer, minor :: integer}
          | token_params
          | type_subtype_params
          | uri_params
          | name_uri_params
          | {delta_seconds :: integer, comment :: binary, params}
          | {timestamp :: integer, delay :: integer}
          | <<_::1>>
          | [name_uri_params, ...]
          | NaiveDateTime.t()

  @type multiple_value ::
          token_params
          | type_subtype_params
          | uri_params
          | name_uri_params
          | via_value
          | auth_params
          | params
          | {code :: integer, agent :: binary, text :: binary}

  @type value ::
          single_value
          | [multiple_value]

  @type t :: %__MODULE__{
          start_line: RequestLine.t() | StatusLine.t(),
          headers: %{header => value},
          body: binary | nil,
          target:
            nil
            | {
                protocol :: atom | binary,
                host :: binary,
                dport :: integer
              }
        }

  @type request :: %__MODULE__{
          start_line: RequestLine.t()
        }

  @type response :: %__MODULE__{
          start_line: StatusLine.t()
        }

  @external_resource protocols_path = Path.join([__DIR__, "..", "..", "c_src", "protocol_list.h"])

  known_protocols =
    for line <- File.stream!(protocols_path, [], :line),
        line |> String.starts_with?("SIP_PROTOCOL") do
      [_, protocol] = Regex.run(~r/SIP_PROTOCOL\(([^,]+)\)/, line)
      atom = protocol |> String.downcase() |> String.to_atom()

      defp string_to_protocol(unquote(protocol)),
        do: unquote(atom)

      protocol
    end

  defp string_to_protocol(string), do: string

  @doc """
  Returns a list of all known transport protocols, as a list of uppercase
  strings.

  ## Example:

      iex> Sippet.Message.known_protocols()
      ["AMQP", "DCCP", "DTLS", "SCTP", "STOMP", "TCP", "TLS", "UDP", "WS", "WSS"]
  """
  @spec known_protocols() :: [String.t()]
  def known_protocols(), do: unquote(known_protocols)

  @doc """
  Converts a string representing a known protocol into an atom, otherwise as an
  uppercase string.

  ## Example:

      iex> Sippet.Message.to_protocol("UDP")
      :udp

      iex> Sippet.Message.to_protocol("uDp")
      :udp

      iex> Sippet.Message.to_protocol("aaa")
      "AAA"

  """
  @spec to_protocol(String.t()) :: protocol
  def to_protocol(string), do: string_to_protocol(string |> String.upcase())

  @external_resource methods_path = Path.join([__DIR__, "..", "..", "c_src", "method_list.h"])

  known_methods =
    for line <- File.stream!(methods_path, [], :line),
        line |> String.starts_with?("SIP_METHOD") do
      [_, method] = Regex.run(~r/SIP_METHOD\(([^,]+)\)/, line)
      atom = method |> String.downcase() |> String.to_atom()

      defp string_to_method(unquote(method)),
        do: unquote(atom)

      method
    end

  defp string_to_method(string), do: string

  @doc """
  Returns a list of all known methods, as a list of uppercase strings.

  ## Example:

      iex> Sippet.Message.known_methods()
      ["ACK", "BYE", "CANCEL", "INFO", "INVITE", "MESSAGE", "NOTIFY", "OPTIONS",
       "PRACK", "PUBLISH", "PULL", "PUSH", "REFER", "REGISTER", "STORE", "SUBSCRIBE",
       "UPDATE"]
  """
  @spec known_methods() :: [String.t()]
  def known_methods(), do: unquote(known_methods)

  @doc """
  Converts a string representing a known method into an atom, otherwise as an
  uppercase string.

  ## Example:

      iex> Sippet.Message.to_method("INVITE")
      :invite

      iex> Sippet.Message.to_method("InViTe")
      :invite

      iex> Sippet.Message.to_method("aaa")
      "AAA"

  """
  @spec to_method(String.t()) :: method
  def to_method(string), do: string_to_method(string |> String.upcase())

  @doc """
  Returns a SIP request created from its basic elements.

  If the `method` is a binary and is a known method, it will be converted to
  a lowercase atom; otherwise, it will be stored as an uppercase string. If
  `method` is an atom, it will be just kept.

  If the `request_uri` is a binary, it will be parsed as a `Sippet.URI` struct.
  Otherwise, if it's already a `Sippet.URI`, it will be stored unmodified.

  The newly created struct has an empty header map, and the body is `nil`.

  ## Examples:

      iex> req1 = Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      %Sippet.Message{body: nil, headers: %{},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}
      iex> req2 = Sippet.Message.build_request("INVITE", "sip:foo@bar.com")
      iex> request_uri = Sippet.URI.parse!("sip:foo@bar.com")
      iex> req3 = Sippet.Message.build_request("INVITE", request_uri)
      iex> req1 == req2 and req2 == req3
      true

  """
  @spec build_request(method, uri | binary) :: request
  def build_request(method, request_uri)

  def build_request(method, request_uri) when is_binary(method) do
    method =
      if String.upcase(method) in known_methods() do
        method |> String.downcase() |> String.to_atom()
      else
        method |> String.upcase()
      end

    do_build_request(method, request_uri)
  end

  def build_request(method, request_uri) when is_atom(method),
    do: do_build_request(method, request_uri)

  defp do_build_request(method, request_uri),
    do: %__MODULE__{start_line: RequestLine.new(method, request_uri)}

  @doc """
  Returns a SIP response created from its basic elements.

  The `status` parameter can be a `Sippet.Message.StatusLine` struct or an
  integer in the range `100..699` representing the SIP response status code.
  In the latter case, a default reason phrase will be obtained from a default
  set; if there's none, then an exception will be raised.

  ## Examples:

      iex> resp1 = Sippet.Message.build_response 200
      %Sippet.Message{body: nil, headers: %{},
       start_line: %Sippet.Message.StatusLine{reason_phrase: "OK", status_code: 200,
        version: {2, 0}}, target: nil}
      iex> status_line = Sippet.Message.StatusLine.new(200)
      iex> resp2 = status_line |> Sippet.Message.build_response
      iex> resp1 == resp2
      true

  """
  @spec build_response(100..699 | StatusLine.t()) :: response | no_return
  def build_response(status)

  def build_response(%StatusLine{} = status_line),
    do: %__MODULE__{start_line: status_line}

  def build_response(status_code) when is_integer(status_code),
    do: build_response(StatusLine.new(status_code))

  @doc """
  Returns a SIP response with a custom reason phrase.

  The `status_code` should be an integer in the range `100..699` representing
  the SIP status code, and `reason_phrase` a binary representing the reason
  phrase text.

      iex> Sippet.Message.build_response 400, "Bad Lorem Ipsum"
      %Sippet.Message{body: nil, headers: %{},
       start_line: %Sippet.Message.StatusLine{reason_phrase: "Bad Lorem Ipsum",
        status_code: 400, version: {2, 0}}, target: nil}

  """
  @spec build_response(100..699, String.t()) :: response
  def build_response(status_code, reason_phrase)
      when is_integer(status_code) and is_binary(reason_phrase),
      do: build_response(StatusLine.new(status_code, reason_phrase))

  @doc ~S'''
  Returns a response created from a request, using a given status code.

  The `request` should be a valid SIP request, or an exception will be thrown.

  The `status` parameter can be a `Sippet.Message.StatusLine` struct or an
  integer in the range `100..699` representing the SIP response status code.
  In the latter case, a default reason phrase will be obtained from a default
  set; if there's none, then an exception will be raised.

  ## Example:

      request =
        """
        REGISTER sips:ss2.biloxi.example.com SIP/2.0
        Via: SIP/2.0/TLS client.biloxi.example.com:5061;branch=z9hG4bKnashds7
        Max-Forwards: 70
        From: Bob <sips:bob@biloxi.example.com>;tag=a73kszlfl
        To: Bob <sips:bob@biloxi.example.com>
        Call-ID: 1j9FpLxk3uxtm8tn@biloxi.example.com
        CSeq: 1 REGISTER
        Contact: <sips:bob@client.biloxi.example.com>
        Content-Length: 0
        """ |> Sippet.Message.parse!()
      request |> Sippet.Message.to_response(200) |> IO.puts
      SIP/2.0 200 OK
      Via: SIP/2.0/TLS client.biloxi.example.com:5061;branch=z9hG4bKnashds7
      To: "Bob" <sips:bob@biloxi.example.com>;tag=K2fizKkV
      From: "Bob" <sips:bob@biloxi.example.com>;tag=a73kszlfl
      CSeq: 1 REGISTER
      Content-Length: 0
      Call-ID: 1j9FpLxk3uxtm8tn@biloxi.example.com


      :ok

  '''
  @spec to_response(request, integer | StatusLine.t()) :: response | no_return
  def to_response(request, status)

  def to_response(request, status_code) when is_integer(status_code),
    do: to_response(request, StatusLine.new(status_code))

  def to_response(
        %__MODULE__{start_line: %RequestLine{}} = request,
        %StatusLine{} = status_line
      ) do
    response =
      status_line
      |> build_response()
      |> put_header(:via, get_header(request, :via))
      |> put_header(:from, get_header(request, :from))
      |> put_header(:to, get_header(request, :to))
      |> put_header(:call_id, get_header(request, :call_id))
      |> put_header(:cseq, get_header(request, :cseq))

    response =
      if status_line.status_code > 100 and
           not Map.has_key?(elem(response.headers.to, 2), "tag") do
        {display_name, uri, params} = response.headers.to
        params = Map.put(params, "tag", create_tag())
        response |> put_header(:to, {display_name, uri, params})
      else
        response
      end

    if has_header?(request, :record_route) do
      response |> put_header(:record_route, get_header(request, :record_route))
    else
      response
    end
  end

  @doc ~S'''
  Returns a response created from a request, using a given status code and a
  custom reason phrase.

  The `request` should be a valid SIP request, or an exception will be thrown.

  The `status_code` parameter should be an integer in the range `100..699`
  representing the SIP response status code. A default reason phrase will be
  obtained from a default set; if there's none, then an exception will be
  raised.

  The `reason_phrase` can be any textual representation of the reason phrase
  the application needs to generate, in binary.

  ## Example:

      request =
        """
        REGISTER sips:ss2.biloxi.example.com SIP/2.0
        Via: SIP/2.0/TLS client.biloxi.example.com:5061;branch=z9hG4bKnashds7
        Max-Forwards: 70
        From: Bob <sips:bob@biloxi.example.com>;tag=a73kszlfl
        To: Bob <sips:bob@biloxi.example.com>
        Call-ID: 1j9FpLxk3uxtm8tn@biloxi.example.com
        CSeq: 1 REGISTER
        Contact: <sips:bob@client.biloxi.example.com>
        Content-Length: 0
        """ |> Sippet.Message.parse!()
      request |> Sippet.Message.to_response(400, "Bad Lorem Ipsum") |> IO.puts
      SIP/2.0 400 Bad Lorem Ipsum
      Via: SIP/2.0/TLS client.biloxi.example.com:5061;branch=z9hG4bKnashds7
      To: "Bob" <sips:bob@biloxi.example.com>;tag=K2fizKkV
      From: "Bob" <sips:bob@biloxi.example.com>;tag=a73kszlfl
      CSeq: 1 REGISTER
      Content-Length: 0
      Call-ID: 1j9FpLxk3uxtm8tn@biloxi.example.com


      :ok

  '''
  @spec to_response(request, integer, String.t()) :: response
  def to_response(request, status_code, reason_phrase)
      when is_integer(status_code) and is_binary(reason_phrase),
      do: to_response(request, StatusLine.new(status_code, reason_phrase))

  @doc """
  Creates a local tag (48-bit random string, 8 characters long).

  ## Example:

      Sippet.Message.create_tag
      "lnTMo9Zn"

  """
  @spec create_tag() :: binary
  def create_tag(), do: do_random_string(48)

  defp do_random_string(length) do
    round(Float.ceil(length / 8))
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Returns the RFC 3261 compliance magic cookie, inserted in via-branch
  parameters.

  ## Example:

      iex> Sippet.Message.magic_cookie
      "z9hG4bK"

  """
  @spec magic_cookie() :: binary
  def magic_cookie(), do: "z9hG4bK"

  @doc """
  Creates an unique local branch (72-bit random string, 7+12 characters long).

  ## Example:

      Sippet.Message.create_branch
      "z9hG4bKuQpiub9h7fBb"

  """
  @spec create_branch() :: binary
  def create_branch(), do: magic_cookie() <> do_random_string(72)

  @doc """
  Creates an unique Call-ID (120-bit random string, 20 characters long).

  ## Example

      Sippet.create_call_id
      "NlV4TfQwkmPlNJkyHPpF"

  """
  @spec create_call_id() :: binary
  def create_call_id(), do: do_random_string(120)

  @doc """
  Shortcut to check if the message is a request.

  ## Examples:

      iex> req = Sippet.Message.build_request :invite, "sip:foo@bar.com"
      iex> req |> Sippet.Message.request?
      true

  """
  @spec request?(t) :: boolean
  def request?(%__MODULE__{start_line: %RequestLine{}} = _), do: true
  def request?(_), do: false

  @doc """
  Shortcut to check if the message is a response.

  ## Examples:

      iex> resp = Sippet.Message.build_response 200
      iex> resp |> Sippet.Message.response?
      true

  """
  @spec response?(t) :: boolean
  def response?(%__MODULE__{start_line: %StatusLine{}} = _), do: true
  def response?(_), do: false

  @doc """
  Returns whether a given `header` exists in the given `message`.

  ## Examples:

      iex> request =
      ...>   Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...>   |> Sippet.Message.put_header(:cseq, {1, :invite})
      iex> request |> Sippet.Message.has_header?(:cseq)
      true

  """
  @spec has_header?(t, header) :: boolean
  def has_header?(message, header),
    do: Map.has_key?(message.headers, header)

  @doc """
  Puts the `value` under `header` on the `message`.

  If the header already exists, it will be overridden.

  ## Examples:

      iex> request = Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      iex> request |> Sippet.Message.put_header(:cseq, {1, :invite})
      %Sippet.Message{body: nil, headers: %{cseq: {1, :invite}},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec put_header(t, header, value) :: t
  def put_header(message, header, value),
    do: %{message | headers: Map.put(message.headers, header, value)}

  @doc """
  Puts the `value` under `header` on the `message` unless the `header` already
  exists.

  ## Examples:

      iex> Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...> |> Sippet.Message.put_new_header(:max_forwards, 70)
      ...> |> Sippet.Message.put_new_header(:max_forwards, 1)
      %Sippet.Message{body: nil, headers: %{max_forwards: 70},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec put_new_header(t, header, value) :: t
  def put_new_header(message, header, value) do
    case has_header?(message, header) do
      true -> message
      false -> put_header(message, header, value)
    end
  end

  @doc """
  Evaluates `fun` and puts the result under `header` in `message` unless
  `header` is already present.

  This function is useful in case you want to compute the value to put under
  `header` only if `header` is not already present (e.g., the value is
  expensive to calculate or generally difficult to setup and teardown again).

  ## Examples:

      iex> Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...> |> Sippet.Message.put_new_lazy_header(:max_forwards, fn -> 70 end)
      ...> |> Sippet.Message.put_new_lazy_header(:max_forwards, fn -> 1 end)
      %Sippet.Message{body: nil, headers: %{max_forwards: 70},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec put_new_lazy_header(t, header, (() -> value)) :: t
  def put_new_lazy_header(message, header, fun) when is_function(fun, 0) do
    case has_header?(message, header) do
      true -> message
      false -> put_header(message, header, fun.())
    end
  end

  @doc """
  Puts the `value` under `header` on the `message`, as front element.

  If the parameter `value` is `nil`, then the empty list will be prefixed to
  the `header`.

  ## Examples:

      iex> Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...> |> Sippet.Message.put_header_front(:content_language, "de-DE")
      ...> |> Sippet.Message.put_header_front(:content_language, "en-US")
      %Sippet.Message{body: nil, headers: %{content_language: ["en-US", "de-DE"]},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec put_header_front(t, header, multiple_value) :: t
  def put_header_front(message, header, value) do
    existing = get_header(message, header, [])

    new_list =
      case value do
        nil -> existing
        _ -> [value | existing]
      end

    put_header(message, header, new_list)
  end

  @doc """
  Puts the `value` under `header` on the `message`, as last element.

  If the parameter `value` is `nil`, then the empty list will be appended to
  the `header`.

  ## Examples:

      iex> Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...> |> Sippet.Message.put_header_back(:content_language, "en-US")
      ...> |> Sippet.Message.put_header_back(:content_language, "de-DE")
      %Sippet.Message{body: nil, headers: %{content_language: ["en-US", "de-DE"]},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec put_header_back(t, header, multiple_value) :: t
  def put_header_back(message, header, value) do
    existing = get_header(message, header, [])

    new_list =
      case value do
        nil -> existing
        _ -> List.foldr(existing, [value], fn x, acc -> [x | acc] end)
      end

    put_header(message, header, new_list)
  end

  @doc """
  Deletes all `header` values in `message`.

  ## Examples:

      iex> request =
      ...>   Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...>   |> Sippet.Message.put_header(:content_language, ["en-US", "de-DE"])
      ...>   |> Sippet.Message.put_header(:max_forwards, 70)
      iex> request |> Sippet.Message.delete_header(:content_language)
      %Sippet.Message{body: nil, headers: %{max_forwards: 70},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec delete_header(t, header) :: t
  def delete_header(message, header) do
    %{message | headers: Map.delete(message.headers, header)}
  end

  @doc """
  Deletes the first value of `header` in `message`.

  ## Examples:

      iex> request =
      ...>   Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...>   |> Sippet.Message.put_header(:content_language, ["en-US", "de-DE"])
      ...>   |> Sippet.Message.put_header(:max_forwards, 70)
      iex> request |> Sippet.Message.delete_header_front(:content_language)
      %Sippet.Message{body: nil,
       headers: %{content_language: ["de-DE"], max_forwards: 70},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec delete_header_front(t, header) :: t
  def delete_header_front(message, header) do
    case get_header(message, header) do
      nil -> message
      [_] -> delete_header(message, header)
      [_ | tail] -> put_header(message, header, tail)
    end
  end

  @doc """
  Deletes the last value of `header` in `message`.

  ## Examples:

      iex> request =
      ...>   Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...>   |> Sippet.Message.put_header(:content_language, ["en-US", "de-DE"])
      ...>   |> Sippet.Message.put_header(:max_forwards, 70)
      iex> request |> Sippet.Message.delete_header_back(:content_language)
      %Sippet.Message{body: nil,
       headers: %{content_language: ["en-US"], max_forwards: 70},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec delete_header_back(t, header) :: t
  def delete_header_back(message, header) do
    case get_header(message, header) do
      nil -> message
      [_] -> delete_header(message, header)
      [_ | _] = values -> put_header(message, header, do_remove_last(values))
    end
  end

  defp do_remove_last(list) when is_list(list) do
    [_ | tail] = Enum.reverse(list)
    Enum.reverse(tail)
  end

  @doc """
  Drops all given `headers` from `message`.

  ## Examples:

      iex> request =
      ...>   Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...>   |> Sippet.Message.put_header(:content_language, ["en-US", "de-DE"])
      ...>   |> Sippet.Message.put_header(:max_forwards, 70)
      iex> request |> Sippet.Message.drop_headers([:content_language, :max_forwards])
      %Sippet.Message{body: nil, headers: %{},
       start_line: %Sippet.Message.RequestLine{method: :invite,
        request_uri: %Sippet.URI{authority: "foo@bar.com", headers: nil,
         host: "bar.com", parameters: nil, port: 5060, scheme: "sip",
         userinfo: "foo"}, version: {2, 0}}, target: nil}

  """
  @spec drop_headers(t, [header]) :: t
  def drop_headers(message, headers),
    do: %{message | headers: Map.drop(message.headers, headers)}

  @doc """
  Fetches all values for a specific `header` and returns it in a tuple.

  If the `header` does not exist, returns `:error`.

  ## Examples:

      iex> request =
      ...>   Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...>   |> Sippet.Message.put_header(:content_language, ["en-US", "de-DE"])
      ...>   |> Sippet.Message.put_header(:max_forwards, 70)
      iex> request |> Sippet.Message.fetch_header(:content_language)
      {:ok, ["en-US", "de-DE"]}
      iex> request |> Sippet.Message.fetch_header(:cseq)
      :error

  """
  @spec fetch_header(t, header) :: {:ok, value} | :error
  def fetch_header(message, header),
    do: Map.fetch(message.headers, header)

  @doc """
  Fetches the first value of a specific `header` and returns it in a tuple.

  If the `header` does not exist, or the value is not a list, returns `:error`.
  If the `header` exists but it is an empty list, returns `{:ok, nil}`.

  ## Examples:

      iex> request =
      ...>   Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...>   |> Sippet.Message.put_header(:content_language, ["en-US", "de-DE"])
      ...>   |> Sippet.Message.put_header(:max_forwards, 70)
      iex> request |> Sippet.Message.fetch_header_front(:content_language)
      {:ok, "en-US"}
      iex> request |> Sippet.Message.fetch_header_front(:max_forwards)
      :error
      iex> request |> Sippet.Message.fetch_header_front(:cseq)
      :error

  """
  @spec fetch_header_front(t, header) ::
          {:ok, multiple_value} | :error
  def fetch_header_front(message, header) do
    case fetch_header(message, header) do
      {:ok, []} ->
        {:ok, nil}

      {:ok, [first | _]} ->
        {:ok, first}

      _otherwise ->
        :error
    end
  end

  @doc """
  Fetches the last value of a specific `header` and returns it in a tuple.

  If the `header` does not exist, or the value is not a list, returns `:error`.
  If the `header` exists but it is an empty list, returns `{:ok, nil}`.

  ## Examples:

      iex> request =
      ...>   Sippet.Message.build_request(:invite, "sip:foo@bar.com")
      ...>   |> Sippet.Message.put_header(:content_language, ["en-US", "de-DE"])
      ...>   |> Sippet.Message.put_header(:max_forwards, 70)
      iex> request |> Sippet.Message.fetch_header_back(:content_language)
      {:ok, "de-DE"}
      iex> request |> Sippet.Message.fetch_header_back(:max_forwards)
      :error
      iex> request |> Sippet.Message.fetch_header_back(:cseq)
      :error

  """
  @spec fetch_header_back(t, header) :: {:ok, multiple_value} | :error
  def fetch_header_back(message, header) do
    case fetch_header(message, header) do
      {:ok, []} ->
        {:ok, nil}

      {:ok, [value]} ->
        {:ok, value}

      {:ok, [_ | rest]} ->
        {:ok, List.last(rest)}

      _otherwise ->
        :error
    end
  end

  @doc """
  Fetches all values for a specific `header` in the given `message`, erroring
  out if `message` doesn't contain `header`.

  If `message` contains the given `header`, all corresponding values are
  returned in a list. If `message` doesn't contain the `header`, a `KeyError`
  exception is raised.
  """
  @spec fetch_header!(t, header) :: value | no_return
  def fetch_header!(message, header),
    do: Map.fetch!(message.headers, header)

  @doc """
  Fetches the first value of a specific `header` in the given `message`, erroring
  out if `message` doesn't contain `header`.

  If `message` contains the given `header`, the first value is returned, which
  may be `nil` case the values list is empty. If `message` doesn't contain the
  `header`, a `KeyError` exception is raised.
  """
  @spec fetch_header_front!(t, header) :: multiple_value | no_return
  def fetch_header_front!(message, header) do
    values = fetch_header!(message, header)

    if Enum.empty?(values) do
      nil
    else
      List.first(values)
    end
  end

  @doc """
  Fetches the last value of a specific `header` in the given `message`, erroring
  out if `message` doesn't contain `header`.

  If `message` contains the given `header`, the last value is returned, which
  may be `nil` case the values list is empty. If `message` doesn't contain the
  `header`, a `KeyError` exception is raised.
  """
  @spec fetch_header_back!(t, header) :: multiple_value | no_return
  def fetch_header_back!(message, header) do
    values = fetch_header!(message, header)

    if Enum.empty?(values) do
      nil
    else
      List.last(values)
    end
  end

  @doc """
  Gets all values for a specific `header` in `message`.

  If `header` is present in `message`, then all values are returned in a list.
  Otherwise, `default` is returned (which is `nil` unless specified otherwise).
  """
  @spec get_header(t, header) :: value | nil
  @spec get_header(t, header, any) :: value | any
  def get_header(message, header, default \\ nil) do
    Map.get(message.headers, header, default)
  end

  @doc """
  Gets the first value of a specific `header` in `message`.

  If `header` is present in `message`, then the first value is returned.
  Otherwise, `default` is returned (which is `nil` unless specified otherwise).
  """
  @spec get_header_front(t, header) :: multiple_value | nil
  @spec get_header_front(t, header, any) :: multiple_value | any
  def get_header_front(message, header, default \\ nil) do
    case get_header(message, header, nil) do
      nil -> default
      values -> List.first(values)
    end
  end

  @doc """
  Gets the last value of a specific `header` in `message`.

  If `header` is present in `message`, then the last value is returned.
  Otherwise, `default` is returned (which is `nil` unless specified otherwise).
  """
  @spec get_header_back(t, header) :: multiple_value | nil
  @spec get_header_back(t, header, any) :: multiple_value | any
  def get_header_back(message, header, default \\ nil) do
    case get_header(message, header, nil) do
      nil -> default
      values -> List.last(values)
    end
  end

  @doc """
  Updates the `header` in `message` with the given function.

  If `header` is present in `message` with value `value`, `fun` is invoked
  with argument `value` and its result is used as the new value of `header`.
  If `header` is not present in `message`, `initial` is inserted as the value
  of `header`.
  """
  @spec update_header(t, header, value | nil, (value -> value)) :: t
  def update_header(message, header, initial \\ nil, fun) do
    %{message | headers: Map.update(message.headers, header, initial, fun)}
  end

  @doc """
  Updates the first `header` value in `message` with the given function.

  If `header` is present in `message` with value `[value]`, `fun` is invoked
  with for first element of `[value]` and its result is used as the new value
  of `header` front.  If `header` is not present in `message`, or it is an empty
  list, `initial` is inserted as the single value of `header`.
  """
  @spec update_header_front(t, header, value | nil, (multiple_value -> multiple_value)) :: t
  def update_header_front(message, header, initial \\ nil, fun)
      when is_function(fun, 1) do
    update_header(message, header, List.wrap(initial), fn [head | tail] -> [fun.(head) | tail] end)
  end

  @doc """
  Updates the last `header` value in `message` with the given function.

  If `header` is present in `message` with value `[value]`, `fun` is invoked
  with for last element of `[value]` and its result is used as the new value of
  `header` back.  If `header` is not present in `message`, or it is an empty
  list, `initial` is inserted as the single value of `header`.
  """
  @spec update_header_back(t, header, value | nil, (multiple_value -> multiple_value)) :: t
  def update_header_back(message, header, initial \\ nil, fun)
      when is_function(fun, 1) do
    update_header(message, header, List.wrap(initial), fn values ->
      do_update_last(values, fun)
    end)
  end

  defp do_update_last(values, fun) do
    [last | tail] = Enum.reverse(values)
    Enum.reduce(tail, [fun.(last)], fn x, acc -> [x | acc] end)
  end

  @doc """
  Returns and removes the values associated with `header` in `message`.

  If `header` is present in `message` with values `[value]`, `{[value],
  new_message}` is returned where `new_message` is the result of removing
  `header` from `message`. If `header` is not present in `message`, `{default,
  message}` is returned.
  """
  @spec pop_header(t, header) :: {value | nil, t}
  @spec pop_header(t, header, any) :: {value | any, t}
  def pop_header(message, header, default \\ nil) do
    {get, new_headers} = Map.pop(message.headers, header, default)
    {get, %{message | headers: new_headers}}
  end

  @doc """
  Returns and removes the first value associated with `header` in `message`.

  If `header` is present in `message` with values `values`,
  `{List.first(values), new_message}` is returned where `new_message` is the
  result of removing `List.first(values)` from `header`.  If `header` is not
  present in `message` or it is an empty list, `{default, message}` is
  returned. When the `header` results in an empty list, `message` gets updated
  by removing the header.
  """
  @spec pop_header_front(t, header) :: {multiple_value | nil, t}
  @spec pop_header_front(t, header, any) :: {multiple_value | any, t}
  def pop_header_front(message, header, default \\ nil) do
    {values, new_headers} = Map.pop(message.headers, header, [])

    case values do
      [] ->
        {default, %{message | headers: new_headers}}

      [value] ->
        {value, %{message | headers: new_headers}}

      [head | tail] ->
        {head, %{message | headers: Map.put(message.headers, header, tail)}}
    end
  end

  @doc """
  Returns and removes the last value associated with `header` in `message`.

  If `header` is present in `message` with values `values`,
  `{List.last(values), new_message}` is returned where `new_message` is the
  result of removing `List.last(values)` from `header`.  If `header` is not
  present in `message` or it is an empty list, `{default, message}` is
  returned. When the `header` results in an empty list, `message` gets updated
  by removing the header.
  """
  @spec pop_header_back(t, header) :: {multiple_value | nil, t}
  @spec pop_header_back(t, header, any) :: {multiple_value | any, t}
  def pop_header_back(message, header, default \\ nil) do
    {values, new_headers} = Map.pop(message.headers, header, [])

    case Enum.reverse(values) do
      [] ->
        {default, %{message | headers: new_headers}}

      [value] ->
        {value, %{message | headers: new_headers}}

      [last | tail] ->
        {last, %{message | headers: Map.put(message.headers, header, Enum.reverse(tail))}}
    end
  end

  @doc """
  Gets the values from `header` and updates it, all in one pass.

  `fun` is called with the current values under `header` in `message` (or `nil`
  if `key` is not present in `message`) and must return a two-element tuple:
  the "get" value (the retrieved values, which can be operated on before being
  returned) and the new values to be stored under `header` in the resulting new
  message. `fun` may also return `:pop`, which means all current values shall
  be removed from `message` and returned (making this function behave like
  `Sippet.Message.pop_header(message, header)`. The returned value is a tuple
  with the "get" value returned by `fun` and a new message with the updated
  values under `header`.
  """
  @spec get_and_update_header(t, header, (value -> {get, value} | :pop)) ::
          {get, t}
        when get: value
  def get_and_update_header(message, header, fun) when is_function(fun, 1) do
    {get, new_headers} = Map.get_and_update(message.headers, header, fun)
    {get, %{message | headers: new_headers}}
  end

  @doc """
  Gets the first value from `header` and updates it, all in one pass.

  `fun` is called with the current first value under `header` in `message` (or
  `nil` if `key` is not present in `message`) and must return a two-element
  tuple: the "get" value (the retrieved value, which can be operated on before
  being returned) and the new value to be stored under `header` in the
  resulting new message. `fun` may also return `:pop`, which means the current
  value shall be removed from `message` and returned (making this function
  behave like `Sippet.Message.pop_header_front(message, header)`. The returned
  value is a tuple with the "get" value returned by `fun` and a new message
  with the updated values under `header`.
  """
  @spec get_and_update_header_front(t, header, (multiple_value -> {get, multiple_value} | :pop)) ::
          {get, t}
        when get: multiple_value
  def get_and_update_header_front(message, header, fun)
      when is_function(fun, 1) do
    {get, new_headers} =
      Map.get_and_update(message.headers, header, &do_get_and_update_header_front(&1, fun))

    {get, %{message | headers: new_headers}}
  end

  defp do_get_and_update_header_front(nil, fun) do
    case fun.(nil) do
      {get, nil} -> {get, []}
      {get, value} -> {get, [value]}
      :pop -> :pop
    end
  end

  defp do_get_and_update_header_front([], fun) do
    case fun.(nil) do
      {get, nil} -> {get, []}
      {get, value} -> {get, [value]}
      :pop -> :pop
    end
  end

  defp do_get_and_update_header_front([head | tail], fun) do
    case fun.(head) do
      {get, nil} -> {get, [tail]}
      {get, value} -> {get, [value | tail]}
      :pop -> {head, tail}
    end
  end

  @doc """
  Gets the last value from `header` and updates it, all in one pass.

  `fun` is called with the current last value under `header` in `message` (or
  `nil` if `key` is not present in `message`) and must return a two-element
  tuple: the "get" value (the retrieved value, which can be operated on before
  being returned) and the new value to be stored under `header` in the
  resulting new message. `fun` may also return `:pop`, which means the current
  value shall be removed from `message` and returned (making this function
  behave like `Sippet.Message.pop_header_back(message, header)`. The returned
  value is a tuple with the "get" value returned by `fun` and a new message
  with the updated values under `header`.
  """
  @spec get_and_update_header_back(t, header, (multiple_value -> {get, multiple_value} | :pop)) ::
          {get, t}
        when get: multiple_value
  def get_and_update_header_back(message, header, fun)
      when is_function(fun, 1) do
    {get, new_headers} =
      Map.get_and_update(message.headers, header, &do_get_and_update_header_back(&1, fun))

    {get, %{message | headers: new_headers}}
  end

  defp do_get_and_update_header_back([], fun) do
    case fun.(nil) do
      {get, value} -> {get, [value]}
      :pop -> :pop
    end
  end

  defp do_get_and_update_header_back(values, fun) do
    [last | tail] = Enum.reverse(values)

    case fun.(last) do
      {get, new_value} -> {get, Enum.reduce(tail, [new_value], fn x, acc -> [x | acc] end)}
      :pop -> {last, Enum.reverse(last)}
    end
  end

  @doc """
  Parses a SIP message header block as received by the transport layer.

  In order to correctly set the message body, you have to verify the
  `:content_length` header; if it exists, it reflects the body size and you
  have to set it manually on the returned message.
  """
  @spec parse(iodata) :: {:ok, t} | {:error, atom}
  def parse(data) do
    binary_data = IO.iodata_to_binary(data)

    case Sippet.Parser.parse(IO.iodata_to_binary(binary_data)) do
      {:ok, message} ->
        case do_parse(message, binary_data) do
          {:error, reason} ->
            {:error, reason}

          message ->
            {:ok, message}
        end

      reason ->
        {:error, reason}
    end
  end

  defp do_parse(message, binary_data) do
    case do_parse_start_line(message.start_line) do
      {:error, reason} ->
        {:error, reason}

      start_line ->
        case do_parse_headers(message.headers) do
          {:error, reason} ->
            {:error, reason}

          headers ->
            %__MODULE__{
              start_line: start_line,
              headers: headers,
              body: get_body(binary_data)
            }
        end
    end
  end

  defp get_body(binary_data) do
    case String.split(binary_data, ~r{\r?\n\r?\n}, parts: 2) do
      [_, body] -> body
      [_] -> nil
    end
  end

  defp do_parse_start_line(%{method: _} = start_line) do
    case URI.parse(start_line.request_uri) do
      {:ok, uri} ->
        %RequestLine{
          method: start_line.method,
          request_uri: uri,
          version: start_line.version
        }

      other ->
        other
    end
  end

  defp do_parse_start_line(%{status_code: _} = start_line) do
    %StatusLine{
      status_code: start_line.status_code,
      reason_phrase: start_line.reason_phrase,
      version: start_line.version
    }
  end

  defp do_parse_headers(%{} = headers),
    do: do_parse_headers(Map.to_list(headers), [])

  defp do_parse_headers([], result), do: Map.new(result)

  defp do_parse_headers([{name, value} | tail], result) do
    case do_parse_header_value(value) do
      {:error, reason} ->
        {:error, reason}

      value ->
        do_parse_headers(tail, [{name, value} | result])
    end
  end

  defp do_parse_header_value(values) when is_list(values),
    do: do_parse_each_header_value(values, [])

  defp do_parse_header_value({{year, month, day}, {hour, minute, second}, microsecond}) do
    NaiveDateTime.from_erl!(
      {{year, month, day}, {hour, minute, second}},
      microsecond
    )
  end

  defp do_parse_header_value({display_name, uri, %{} = parameters}) do
    case URI.parse(uri) do
      {:ok, uri} ->
        {display_name, uri, parameters}

      other ->
        other
    end
  end

  defp do_parse_header_value(value), do: value

  defp do_parse_each_header_value([], result), do: Enum.reverse(result)

  defp do_parse_each_header_value([head | tail], result) do
    case do_parse_header_value(head) do
      {:error, reason} ->
        {:error, reason}

      value ->
        do_parse_each_header_value(tail, [value | result])
    end
  end

  @doc """
  Parses a SIP message header block as received by the transport layer.

  Raises if the string is an invalid SIP header.

  In order to correctly set the message body, you have to verify the
  `:content_length` header; if it exists, it reflects the body size and you
  have to set it manually on the returned message.
  """
  @spec parse!(String.t() | charlist) :: t | no_return
  def parse!(data) do
    case parse(data) do
      {:ok, message} ->
        message

      {:error, reason} ->
        raise ArgumentError,
              "cannot convert #{inspect(data)} to SIP " <>
                "message, reason: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the string representation of the given `Sippet.Message` struct.
  """
  @spec to_string(t) :: binary
  defdelegate to_string(value), to: String.Chars.Sippet.Message

  @doc """
  Returns the iodata representation of the given `Sippet.Message` struct.
  """
  @spec to_iodata(t) :: iodata
  def to_iodata(%Sippet.Message{} = message) do
    start_line =
      case message.start_line do
        %RequestLine{} -> RequestLine.to_iodata(message.start_line)
        %StatusLine{} -> StatusLine.to_iodata(message.start_line)
      end

    # includes a Content-Length header case it does not have one
    message =
      if message.headers |> Map.has_key?(:content_length) do
        message
      else
        len = if(message.body == nil, do: 0, else: String.length(message.body))
        %{message | headers: Map.put(message.headers, :content_length, len)}
      end

    [
      start_line,
      "\r\n",
      do_headers(message.headers),
      "\r\n",
      if(message.body == nil, do: "", else: message.body)
    ]
  end

  defp do_headers(%{} = headers), do: do_headers(Map.to_list(headers), [])
  defp do_headers([], result), do: result

  defp do_headers([{name, value} | tail], result),
    do: do_headers(tail, [do_header(name, value) | result])

  defp do_header(name, value) do
    {name, multiple} =
      case name do
        :accept -> {"Accept", true}
        :accept_encoding -> {"Accept-Encoding", true}
        :accept_language -> {"Accept-Language", true}
        :alert_info -> {"Alert-Info", true}
        :allow -> {"Allow", true}
        :authentication_info -> {"Authentication-Info", false}
        :authorization -> {"Authorization", false}
        :call_id -> {"Call-ID", true}
        :call_info -> {"Call-Info", true}
        :contact -> {"Contact", true}
        :content_disposition -> {"Content-Disposition", true}
        :content_encoding -> {"Content-Encoding", true}
        :content_language -> {"Content-Language", true}
        :content_length -> {"Content-Length", true}
        :content_type -> {"Content-Type", true}
        :cseq -> {"CSeq", true}
        :date -> {"Date", true}
        :error_info -> {"Error-Info", true}
        :event -> {"Event", true}
        :expires -> {"Expires", true}
        :from -> {"From", true}
        :in_reply_to -> {"In-Reply-To", true}
        :max_forwards -> {"Max-Forwards", true}
        :mime_version -> {"MIME-Version", true}
        :min_expires -> {"Min-Expires", true}
        :organization -> {"Organization", true}
        :priority -> {"Priority", true}
        :p_asserted_identity -> {"P-Asserted-Identity", true}
        :proxy_authenticate -> {"Proxy-Authenticate", false}
        :proxy_authorization -> {"Proxy-Authorization", false}
        :proxy_require -> {"Proxy-Require", true}
        :reason -> {"Reason", true}
        :record_route -> {"Record-Route", true}
        :reply_to -> {"Reply-To", true}
        :require -> {"Require", true}
        :retry_after -> {"Retry-After", true}
        :route -> {"Route", true}
        :server -> {"Server", true}
        :subject -> {"Subject", true}
        :supported -> {"Supported", true}
        :timestamp -> {"Timestamp", true}
        :to -> {"To", true}
        :unsupported -> {"Unsupported", true}
        :user_agent -> {"User-Agent", true}
        :via -> {"Via", true}
        :warning -> {"Warning", true}
        :www_authenticate -> {"WWW-Authenticate", false}
        other -> {other, true}
      end

    if multiple do
      [name, ": ", do_header_values(value, []), "\r\n"]
    else
      do_one_per_line(name, value)
    end
  end

  defp do_header_values([], values), do: values |> Enum.reverse()

  defp do_header_values([head | tail], values),
    do: do_header_values(tail, do_join(do_header_value(head), values, ", "))

  defp do_header_values(value, _), do: do_header_value(value)

  defp do_header_value(value) when is_binary(value), do: value

  defp do_header_value(value) when is_integer(value), do: Integer.to_string(value)

  defp do_header_value({sequence, method}) when is_integer(sequence),
    do: [Integer.to_string(sequence), " ", upcase_atom_or_string(method)]

  defp do_header_value({major, minor})
       when is_integer(major) and is_integer(minor),
       do: [Integer.to_string(major), ".", Integer.to_string(minor)]

  defp do_header_value({token, %{} = parameters}) when is_binary(token),
    do: [token, do_parameters(parameters)]

  defp do_header_value({{type, subtype}, %{} = parameters})
       when is_binary(type) and is_binary(subtype),
       do: [type, "/", subtype, do_parameters(parameters)]

  defp do_header_value({display_name, %URI{} = uri, %{} = parameters})
       when is_binary(display_name) do
    [
      if(display_name == "", do: "", else: ["\"", display_name, "\" "]),
      "<",
      URI.to_string(uri),
      ">",
      do_parameters(parameters)
    ]
  end

  defp do_header_value({delta_seconds, comment, %{} = parameters})
       when is_integer(delta_seconds) and is_binary(comment) do
    [
      Integer.to_string(delta_seconds),
      if(comment != "", do: [" (", comment, ") "], else: ""),
      do_parameters(parameters)
    ]
  end

  defp do_header_value({timestamp, delay})
       when is_float(timestamp) and is_float(delay) do
    [Float.to_string(timestamp), if(delay > 0, do: [" ", Float.to_string(delay)], else: "")]
  end

  defp do_header_value({{major, minor}, protocol, {host, port}, %{} = parameters})
       when is_integer(major) and is_integer(minor) and
              is_binary(host) and is_integer(port) do
    [
      "SIP/",
      Integer.to_string(major),
      ".",
      Integer.to_string(minor),
      "/",
      upcase_atom_or_string(protocol),
      " ",
      host,
      if(port > 0, do: [":", Integer.to_string(port)], else: ""),
      do_parameters(parameters)
    ]
  end

  defp do_header_value({code, agent, text})
       when is_integer(code) and is_binary(agent) and is_binary(text) do
    [Integer.to_string(code), " ", agent, " \"", text, "\""]
  end

  defp do_header_value(%NaiveDateTime{} = value) do
    day_of_week =
      case Date.day_of_week(NaiveDateTime.to_date(value)) do
        1 -> "Mon"
        2 -> "Tue"
        3 -> "Wed"
        4 -> "Thu"
        5 -> "Fri"
        6 -> "Sat"
        7 -> "Sun"
      end

    month =
      case value.month do
        1 -> "Jan"
        2 -> "Feb"
        3 -> "Mar"
        4 -> "Apr"
        5 -> "May"
        6 -> "Jun"
        7 -> "Jul"
        8 -> "Aug"
        9 -> "Sep"
        10 -> "Oct"
        11 -> "Nov"
        12 -> "Dec"
      end

    # Microsecond is explicitly removed here, as the RFC 3261 does not define
    # it. Therefore, while it is accepted, it won't be forwarded.
    [
      day_of_week,
      ", ",
      String.pad_leading(Integer.to_string(value.day), 2, "0"),
      " ",
      month,
      " ",
      Integer.to_string(value.year),
      " ",
      String.pad_leading(Integer.to_string(value.hour), 2, "0"),
      ":",
      String.pad_leading(Integer.to_string(value.minute), 2, "0"),
      ":",
      String.pad_leading(Integer.to_string(value.second), 2, "0"),
      " GMT"
    ]
  end

  defp do_one_per_line(name, %{} = value),
    do: [name, ": ", do_one_per_line_value(value), "\r\n"]

  defp do_one_per_line(name, values) when is_list(values),
    do: do_one_per_line(name, values |> Enum.reverse(), [])

  defp do_one_per_line(_, [], result), do: result

  defp do_one_per_line(name, [head | tail], result),
    do: do_one_per_line(name, tail, [name, ": ", do_one_per_line_value(head), "\r\n" | result])

  defp do_one_per_line_value(%{} = parameters),
    do: do_one_per_line_value(Map.to_list(parameters), [])

  defp do_one_per_line_value({scheme, %{} = parameters}),
    do: [scheme, " ", do_auth_parameters(parameters)]

  defp do_one_per_line_value([], result), do: result

  defp do_one_per_line_value([{name, value} | tail], result) do
    do_one_per_line_value(tail, do_join([name, "=", value], result, ", "))
  end

  defp do_parameters(%{} = parameters),
    do: do_parameters(Map.to_list(parameters), [])

  defp do_parameters([], result), do: result

  defp do_parameters([{name, ""} | tail], result),
    do: do_parameters(tail, [";", name | result])

  defp do_parameters([{name, value} | tail], result),
    do: do_parameters(tail, [";", name, "=", value | result])

  defp do_join(head, [], _joiner), do: [head]
  defp do_join(head, tail, joiner), do: [head, joiner | tail]

  defp upcase_atom_or_string(s),
    do: if(is_atom(s), do: String.upcase(Atom.to_string(s)), else: s)

  defp do_auth_parameters(%{} = parameters),
    do: do_auth_parameters(Map.to_list(parameters), [])

  defp do_auth_parameters([], result), do: result |> Enum.reverse()

  defp do_auth_parameters([{name, value} | tail], [])
       when name in ["username", "realm", "nonce", "uri", "response", "cnonce", "opaque"],
    do: do_auth_parameters(tail, [[name, "=\"", value, "\""]])

  defp do_auth_parameters([{name, value} | tail], []),
    do: do_auth_parameters(tail, [[name, "=", value]])

  defp do_auth_parameters([{name, value} | tail], result)
       when name in ["username", "realm", "nonce", "uri", "response", "cnonce", "opaque"],
    do: do_auth_parameters(tail, [[",", name, "=\"", value, "\""] | result])

  defp do_auth_parameters([{name, value} | tail], result),
    do: do_auth_parameters(tail, [[",", name, "=", value] | result])

  @doc """
  Checks whether a message is valid.
  """
  @spec valid?(t) :: boolean
  def valid?(message) do
    case validate(message) do
      :ok -> true
      _ -> false
    end
  end

  @doc """
  Checks whether a message is valid, also checking if it corresponds to the
  indicated incoming transport tuple `{protocol, host, port}`.
  """
  @spec valid?(t, {protocol, host :: String.t(), port :: integer}) :: boolean
  def valid?(message, from) do
    case validate(message, from) do
      :ok -> true
      _ -> false
    end
  end

  @doc """
  Validates if a message is valid, returning errors if found.
  """
  @spec validate(t) :: :ok | {:error, reason :: term}
  def validate(message) do
    validators = [
      &has_valid_start_line_version/1,
      &has_required_headers/1,
      &has_valid_body/1,
      &has_tag_on(&1, :from)
    ]

    validators =
      if request?(message) do
        validators ++
          [
            &has_matching_cseq/1
          ]
      else
        validators
      end

    do_validate(validators, message)
  end

  defp do_validate([], _message), do: :ok

  defp do_validate([f | rest], message) do
    case f.(message) do
      :ok -> do_validate(rest, message)
      other -> other
    end
  end

  defp has_valid_start_line_version(message) do
    %{version: version} = message.start_line

    if version == {2, 0} do
      :ok
    else
      {:error, "invalid status line version #{inspect(version)}"}
    end
  end

  defp has_required_headers(message) do
    required = [:to, :from, :cseq, :call_id, :via]

    missing_headers =
      for header <- required, not (message |> has_header?(header)) do
        header
      end

    if Enum.empty?(missing_headers) do
      :ok
    else
      {:error, "missing headers: #{inspect(missing_headers)}"}
    end
  end

  defp has_valid_body(message) do
    case message.headers do
      %{content_length: content_length} ->
        cond do
          message.body != nil and byte_size(message.body) == content_length ->
            :ok

          message.body == nil and content_length == 0 ->
            :ok

          true ->
            {:error, "Content-Length and message body size do not match"}
        end

      _otherwise ->
        cond do
          message.body == nil ->
            :ok

          message.headers.via |> List.last() |> elem(1) == :udp ->
            # It is OK to not have Content-Length in an UDP message
            :ok

          true ->
            {:error, "No Content-Length header, but body is not nil"}
        end
    end
  end

  defp has_tag_on(message, header) do
    {_display_name, _uri, params} = message.headers[header]

    case params do
      %{"tag" => value} ->
        if String.length(value) > 0 do
          :ok
        else
          {:error, "empty #{inspect(header)} tag"}
        end

      _otherwise ->
        {:error, "#{inspect(header)} does not have tag"}
    end
  end

  defp has_matching_cseq(request) do
    method = request.start_line.method

    case request.headers.cseq do
      {_sequence, ^method} ->
        :ok

      _ ->
        {:error, "CSeq method and request method do no match"}
    end
  end

  @doc """
  Validates if a message is valid, also checking if it corresponds to the
  indicated incoming transport tuple `{protocol, host, port}`. It returns the
  error if found.
  """
  @spec validate(t, {protocol, host :: String.t(), port :: integer}) ::
          :ok | {:error, reason :: term}
  def validate(message, from) do
    case validate(message) do
      :ok ->
        validators = [
          &has_valid_via(&1, from)
        ]

        do_validate(validators, message)

      other ->
        other
    end
  end

  defp has_valid_via(message, {protocol1, _ip, _port}) do
    {_version, protocol2, _sent_by, _params} = hd(message.headers.via)

    if protocol1 != protocol2 do
      {:error, "Via protocol doesn't match transport protocol"}
    else
      has_valid_via(message, message.headers.via)
    end
  end

  defp has_valid_via(_, []), do: :ok

  defp has_valid_via(message, [via | rest]) do
    {version, _protocol, _sent_by, params} = via

    if version != {2, 0} do
      {:error, "Via version #{inspect(version)} is unknown"}
    else
      case params do
        %{"branch" => branch} ->
          if branch |> String.starts_with?("z9hG4bK") do
            has_valid_via(message, rest)
          else
            {:error, "Via branch doesn't start with the magic cookie"}
          end

        _otherwise ->
          {:error, "Via header doesn't have branch parameter"}
      end
    end
  end

  @doc """
  Extracts the remote address and port from an incoming request inspecting the
  `Via` header. If `;rport` is present, use it instead of the topmost `Via`
  port, if `;received` is present, use it instead of the topmost `Via` host.
  """
  @spec get_remote(request) ::
          {:ok, {protocol :: atom | binary, host :: binary, port :: integer}}
          | {:error, reason :: term}
  def get_remote(%__MODULE__{start_line: %RequestLine{}, headers: %{via: [topmost_via | _]}}) do
    {_version, protocol, {host, port}, params} = topmost_via

    host =
      case params do
        %{"received" => received} ->
          received

        _otherwise ->
          host
      end

    port =
      case params do
        %{"rport" => rport} ->
          rport |> String.to_integer()

        _otherwise ->
          port
      end

    {:ok, {protocol, host, port}}
  end

  def get_remote(%__MODULE__{start_line: %RequestLine{}}),
    do: {:error, "Missing Via header"}

  def get_remote(%__MODULE__{}),
    do: {:error, "Not a request"}

  @doc """
  Fetches the value for a specific `key` in the given `message`.
  """
  def fetch(%__MODULE__{} = message, key), do: Map.fetch(message, key)

  @doc """
  Gets the value from key and updates it, all in one pass.

  About the same as `Map.get_and_update/3` except that this function actually
  does not remove the key from the struct case the passed function returns
  `:pop`; it puts `nil` for `:start_line`, `:body` and `:target` ands `%{}` for
  the `:headers` key.
  """
  def get_and_update(%__MODULE__{} = message, key, fun)
      when key in [:start_line, :headers, :body, :target] do
    current = message[key]

    case fun.(current) do
      {get, update} ->
        {get, message |> Map.put(key, update)}

      :pop ->
        {current, pop(message, key)}

      other ->
        raise "the given function must return a two-element tuple or :pop, got: #{inspect(other)}"
    end
  end

  @doc """
  Returns and removes the value associated with `key` in `message`.

  About the same as `Map.pop/3` except that this function actually does not
  remove the key from the struct case the passed function returns `:pop`; it
  puts `nil` for `:start_line`, `:body` and `:target` ands `%{}` for the
  `:headers` key.
  """
  def pop(message, key, default \\ nil)

  def pop(%__MODULE__{} = message, :headers, default) when default == nil or is_map(default),
    do: {message[:headers], %{message | headers: %{}}}

  def pop(%__MODULE__{}, :headers, _),
    do: raise("invalid :default, :headers must be nil or a map")

  def pop(%__MODULE__{} = message, key, nil) when key in [:start_line, :body, :target],
    do: {message[key], %{message | key => nil}}

  def pop(%__MODULE__{} = message, :start_line, %RequestLine{} = start_line),
    do: {message[:start_line], %{message | start_line: start_line}}

  def pop(%__MODULE__{} = message, :start_line, %StatusLine{} = start_line),
    do: {message[:start_line], %{message | start_line: start_line}}

  def pop(%__MODULE__{}, :start_line, _),
    do: raise("invalid :default, :start_line must be nil, RequestLine or StatusLine")

  def pop(%__MODULE__{} = message, :body, default) when is_binary(default),
    do: {message[:body], %{message | body: default}}

  def pop(%__MODULE__{}, :body, _),
    do: raise("invalid :default, :body must be nil or binary")

  def pop(%__MODULE__{} = message, :target, {_protocol, _host, _port} = default),
    do: {message[:target], %{message | target: default}}

  def pop(%__MODULE__{}, :target, _),
    do: raise("invalid :default, :target must be nil or {protocol, host, port} tuple")
end

defimpl String.Chars, for: Sippet.Message do
  def to_string(%Sippet.Message{} = message),
    do: message |> Sippet.Message.to_iodata() |> IO.iodata_to_binary()
end
