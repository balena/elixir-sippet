defmodule Sippet.URI do
  @moduledoc """
  Utilities for working with SIP-URIs.

  This module provides functions for working with URIs (for example, parsing
  SIP-URIs, encoding parameters or header strings).
  """

  defstruct [
    scheme: nil, userinfo: nil,
    authority: nil, parameters: nil,
    headers: nil, host: nil, port: nil,
  ]

  @type t :: %__MODULE__{
    scheme: nil | binary,
    userinfo: nil | binary,
    authority: nil | binary,
    parameters: nil | binary,
    headers: nil | binary,
    host: nil | binary,
    port: nil | :inet.port_number
  }

  @doc """
  Returns the default port for a given SIP scheme.
  If the scheme is unknown to the `Sippet.URI` module, this function returns
  `nil`.

  ## Examples

      iex> Sippet.URI.default_port("sip")
      5060
      iex> Sippet.URI.default_port("ponzi")
      nil
  """
  @spec default_port(binary) :: nil | non_neg_integer
  def default_port(scheme) do
    case scheme do
      "sip" -> 5060
      "sips" -> 5061
      _ -> nil
    end
  end

  @doc """
  Encodes an enumerable into a "uri-parameters" string.

  Takes an enumerable that enumerates as a list of two-element tuples (e.g., a
  map or a keyword list) and returns a string in the form of
  `;key1=value1;key2=value2...` where keys and values are encoded as per
  `encode_paramchar/1`. Keys and values can be any term that implements the
  `String.Chars` protocol, except lists which are explicitly forbidden.

  ## Examples

      iex> hd = %{"foo" => 1, "bar" => 2}
      iex> Sippet.URI.encode_parameters(hd)
      ";bar=2;foo=1"
      iex> parameters = %{"key" => "value with spaces"}
      iex> Sippet.URI.encode_parameters(parameters)
      ";key=value%20with%20spaces"
      iex> Sippet.URI.encode_parameters %{key: [:a, :list]}
      ** (ArgumentError) encode_parameters/1 values cannot be lists, got: [:a, :list]
  """
  @spec encode_parameters(term) :: binary
  def encode_parameters(enumerable),
    do: wrap("encode_parameters/1", ";", ";", enumerable, &encode_paramchar/1)

  defp wrap(function_name, first_character, separator, enumerable, encode) do
    first_character <> Enum.map_join(enumerable, separator,
      &encode_pair(function_name, encode, &1))
  end

  defp encode_pair(function_name, _encode, {key, _}) when is_list(key) do
    raise ArgumentError, function_name <> " keys cannot be lists, "
                         <> "got: #{inspect key}"
  end

  defp encode_pair(function_name, _encode, {_, value}) when is_list(value) do
    raise ArgumentError, function_name <> " values cannot be lists, "
                         <> "got: #{inspect value}"
  end

  defp encode_pair(_function_name, encode, {key, nil}) do
    encode.(Kernel.to_string(key))
  end

  defp encode_pair(_function_name, encode, {key, value}) do
    encode.(Kernel.to_string(key)) <>
      "=" <> encode.(Kernel.to_string(value))
  end

  @doc """
  Decodes a "uri-parameters" string into a map.

  Given a "uri-parameters" string of the form of `;key1=value1;key2=value2...`,
  this function inserts each key-value pair in the query string as one entry in
  the given `map`. Keys and values in the resulting map will be binaries. Keys
  and values will be percent-unescaped.

  Use `parameters_decoder/1` if you want to iterate over each value manually.

  ## Examples

      iex> Sippet.URI.decode_parameters(";foo=1;bar=2")
      %{"bar" => "2", "foo" => "1"}

  """
  @spec decode_parameters(binary) :: map
  def decode_parameters(parameters, map \\ %{}) do
    if parameters == nil do
      map
    else
      unwrap("decode_parameters/1", ";", ";", parameters, map)
    end
  end

  defp unwrap(function_name, first_character, separator, string, map) do
    middle = remove_first_char(function_name, string, first_character)
    decode_into_map(middle, map, separator)
  end

  defp remove_first_char(function_name, string, first_character) do
    cond do
      string == "" -> ""
      String.starts_with?(string, first_character) ->
        String.slice(string, 1, String.length(string) - 1)
      :otherwise ->
        raise ArgumentError,
            function_name <> " string has to start with '"
            <> first_character <> "', got: #{inspect string}"
    end
  end

  defp decode_into_map(parameters, map, separator) do
    case decode_next_pair(parameters, separator) do
      nil -> map
      {{key, value}, rest} ->
        decode_into_map(rest, Map.put(map, key, value), separator)
    end
  end

  defp decode_next_pair("", _separator), do: nil
  defp decode_next_pair(string, separator) do
    {undecoded_next_pair, rest} =
      case :binary.split(string, separator) do
        [next_pair, rest] -> {next_pair, rest}
        [next_pair]       -> {next_pair, ""}
      end

    next_pair =
      case :binary.split(undecoded_next_pair, "=") do
        [key, value] -> {percent_unescape(key), percent_unescape(value)}
        [key]        -> {percent_unescape(key), nil}
      end

    {next_pair, rest}
  end

  @doc """
  Returns a stream of two-element tuples representing key-value pairs in the
  given `parameters`.

  Key and value in each tuple will be binaries and will be percent-unescaped.

  ## Examples

      iex> Sippet.URI.parameters_decoder(";foo=1;bar=2") |> Enum.to_list()
      [{"foo", "1"}, {"bar", "2"}]

  """
  @spec parameters_decoder(binary) :: Enumerable.t
  def parameters_decoder(parameters) when is_binary(parameters) do
    middle = remove_first_char("parameters_decoder/1", parameters, ";")
    Stream.unfold(middle, &decode_next_pair(&1, ";"))
  end

  @doc """
  Encodes an enumerable into a "headers" string.

  Takes an enumerable that enumerates as a list of two-element tuples (e.g., a
  map or a keyword list) and returns a string in the form of
  `?key1=value1&key2=value2...` where keys and values are encoded as per
  `encode_header/1`. Keys and values can be any term that implements the
  `String.Chars` protocol, except lists which are explicitly forbidden.

  ## Examples

      iex> hd = %{"foo" => 1, "bar" => 2}
      iex> Sippet.URI.encode_headers(hd)
      "?bar=2&foo=1"
      iex> headers = %{"key" => "value with spaces"}
      iex> Sippet.URI.encode_headers(headers)
      "?key=value%20with%20spaces"
      iex> Sippet.URI.encode_headers %{key: [:a, :list]}
      ** (ArgumentError) encode_headers/1 values cannot be lists, got: [:a, :list]

  """
  @spec encode_headers(term) :: binary
  def encode_headers(enumerable),
    do: wrap("encode_headers/1", "?", "&", enumerable, &encode_hnvchar/1)

  @doc """
  Decodes a "headers" string into a map.

  Given a "headers" string of the form of `?key1=value1&key2=value2...`,
  this function inserts each key-value pair in the query string as one entry in
  the given `map`. Keys and values in the resulting map will be binaries. Keys
  and values will be percent-unescaped.

  Use `headers_decoder/1` if you want to iterate over each value manually.

  ## Examples

      iex> Sippet.URI.decode_headers("?foo=1&bar=2")
      %{"bar" => "2", "foo" => "1"}
  """
  @spec decode_headers(binary) :: map
  def decode_headers(headers, map \\ %{}) do
    if headers == nil do
      map
    else
      unwrap("decode_headers/1", "?", "&", headers, map)
    end
  end

  @doc """
  Returns a stream of two-element tuples representing key-value pairs in the
  given `headers`.

  Key and value in each tuple will be binaries and will be percent-unescaped.

  ## Examples

      iex> Sippet.URI.headers_decoder("?foo=1&bar=2") |> Enum.to_list()
      [{"foo", "1"}, {"bar", "2"}]
  """
  @spec headers_decoder(binary) :: Enumerable.t
  def headers_decoder(headers) when is_binary(headers) do
    middle = remove_first_char("headers_decoder/1", headers, "?")
    Stream.unfold(middle, &decode_next_pair(&1, "&"))
  end

  @doc """
  Encodes a string as "paramchar".
  
  ## Example
  
      iex> Sippet.URI.encode_paramchar("put: it+й")
      "put:%20it+%D0%B9"
  
  """
  @spec encode_paramchar(binary) :: binary
  def encode_paramchar(string) when is_binary(string) do
    URI.encode(string, fn(char) ->
      cond do
        char_param_unreserved?(char) -> true
        char_unreserved?(char) -> true
        :otherwise -> false
      end
    end)
  end

  @doc """
  Encodes a string as "hname" / "hvalue".

  ## Example

      iex> Sippet.URI.encode_hnvchar("put: it+й")
      "put:%20it+%D0%B9"

  """
  @spec encode_hnvchar(binary) :: binary
  def encode_hnvchar(string) when is_binary(string) do
    URI.encode(string, fn(char) ->
      cond do
        char_hnv_unreserved?(char) -> true
        char_unreserved?(char) -> true
        :otherwise -> false
      end
    end)
  end

  @doc """
  Decodes an encoded string, transforming any percent encoding back to
  corresponding characters.

  ## Examples

      iex> Sippet.URI.percent_unescape("%3Call%20in%2F")
      "<all in/"
  """
  @spec percent_unescape(binary) :: binary
  def percent_unescape(string), do: URI.decode(string)

  @doc """
  Checks if the character is an "unreserved" character in a SIP-URI.

  ## Examples

      iex> Sippet.URI.char_unreserved?(?~)
      true

  """
  @spec char_unreserved?(char) :: boolean
  def char_unreserved?(char) when char in 0..0x10FFFF do
    cond do
      char in ?a..?z -> true
      char in ?A..?Z -> true
      char in ?0..?9 -> true
      char in '-_.!~*\'()' -> true
      :otherwise -> false
    end
  end

  @doc """
  Checks if the character is an "param-unreserved" character in a SIP-URI.

  ## Examples

      iex> Sippet.URI.char_param_unreserved?(?~)
      false

  """
  @spec char_param_unreserved?(char) :: boolean
  def char_param_unreserved?(char) when char in 0..0x10FFFF,
    do: char in '[]/:&+$'

  @doc """
  Checks if the character is an "hnv-unreserved" character in a SIP-URI.

  ## Examples

      iex> Sippet.URI.char_hnv_unreserved?(?:)
      true
  """
  @spec char_hnv_unreserved?(char) :: boolean
  def char_hnv_unreserved?(char) when char in 0..0x10FFFF,
    do: char in '[]/?:+$'

  @doc """
  Parses a well-formed SIP-URI reference into its components.

  Note this function expects a well-formed SIP-URI and does not perform
  any validation. See the "Examples" section below for examples of how
  `Sippet.URI.parse/1` can be used to parse a wide range of URIs.
  When a SIP-URI is given without a port, the value returned by
  `Sippet.URI.default_port/1` for the SIP-URI's scheme is used for the `:port`
  field. If a `%Sippet.URI{}` struct is given to this function, this function
  returns it unmodified.

  ## Examples

      iex> Sippet.URI.parse("sip:user@host?Call-Info=%3Chttp://www.foo.com%3E&Subject=foo")
      {:ok, %Sippet.URI{scheme: "sip", userinfo: "user", authority: "user@host",
                  host: "host", port: 5060, parameters: nil,
                  headers: "?Call-Info=%3Chttp://www.foo.com%3E&Subject=foo"}}
      iex> Sippet.URI.parse("sip:user@host;transport=FOO")
      {:ok, %Sippet.URI{scheme: "sip", userinfo: "user", authority: "user@host",
                  host: "host", port: 5060, parameters: ";transport=FOO",
                  headers: nil}}
      iex> Sippet.URI.parse("sip:user@host")
      {:ok, %Sippet.URI{scheme: "sip", userinfo: "user", authority: "user@host",
                  host: "host", port: 5060, parameters: nil,
                  headers: nil}}
  """
  @spec parse(t | binary) :: {:ok, t} | {:error, reason :: term}
  def parse(%URI{} = uri), do: uri

  def parse(string) when is_binary(string) do
    regex = ~r{^(([^:;?]+):)([^;?]+)([^?]*)(\?.*)?}
    parts = nillify(Regex.run(regex, string))
    case parts do
      {:error, reason} ->
        {:error, reason}
      _otherwise ->
        destructure [_, _, scheme, authority, parameters, headers], parts
        {userinfo, host, port} = split_authority(authority)

        scheme = scheme && String.downcase(scheme)
        port   = port || (scheme && default_port(scheme))

        {:ok, %Sippet.URI{
          scheme: scheme, userinfo: userinfo,
          authority: authority, parameters: parameters,
          headers: headers, host: host, port: port
        }}
    end
  end

  @doc """
  Parses a well-formed SIP-URI reference into its components.

  If invalid, raises an exception.
  """
  @spec parse!(t | binary) :: t | no_return
  def parse!(%URI{} = uri), do: uri

  def parse!(string) when is_binary(string) do
    case parse(string) do
      {:ok, message} ->
        message
      {:error, reason} ->
        raise ArgumentError, "cannot convert #{inspect string} to SIP-URI, " <>
            "reason: #{inspect reason}"
    end
  end

  # Split an authority into its userinfo, host and port parts.
  defp split_authority(string) do
    components = Regex.run(~r/(^(.*)@)?(\[[a-zA-Z0-9:.]*\]|[^:]*)(:(\d*))?/, string || "")

    destructure [_, _, userinfo, host, _, port], nillify(components)
    host = if host, do: host |> String.trim_leading("[") |> String.trim_trailing("]")
    port = if port, do: String.to_integer(port)

    {userinfo, host, port}
  end

  # Regex.run returns empty strings sometimes. We want
  # to replace those with nil for consistency.
  defp nillify(nil), do: {:error, :invalid}
  defp nillify(list) do
    for string <- list do
      if byte_size(string) > 0, do: string
    end
  end

  @doc """
  Returns the string representation of the given `Sippet.URI` struct.

  ## Examples

      iex> Sippet.URI.to_string(Sippet.URI.parse!("sip:foo@bar.com"))
      "sip:foo@bar.com"
      iex> Sippet.URI.to_string(%URI{scheme: "foo", host: "bar.baz"})
      "foo:bar.baz"

  """
  @spec to_string(t) :: binary
  defdelegate to_string(uri), to: String.Chars.Sippet.URI

  @doc """
  Checks whether two SIP-URIs are equivalent.

  This function follows the RFC 3261 rules specified in section 19.1.4.

  ## Examples

      iex> a = Sippet.URI.parse!("sip:%61lice@atlanta.com;transport=TCP")
      iex> b = Sippet.URI.parse!("sip:alice@atlanta.com;transport=tcp")
      iex> Sippet.URI.equivalent(a, b)
      true

  """
  @spec equivalent(t, t) :: boolean
  def equivalent(a, b) do
    quite_similar(a, b) and
    authority_hostport(a.authority) == authority_hostport(b.authority)
  end

  defp quite_similar(a, b, default_parameters \\ %{}) do
    String.downcase(a.scheme) == String.downcase(b.scheme) and
      ((a.userinfo == nil and b.userinfo == nil) or
       (a.userinfo != nil and b.userinfo != nil and
        percent_unescape(a.userinfo) == percent_unescape(b.userinfo)) or
        false) and
    String.downcase(a.host) == String.downcase(b.host) and
    a.port == b.port and
    equivalent_parameters(decode_parameters(a.parameters),
                          decode_parameters(b.parameters),
                          default_parameters) and
    equivalent_headers(decode_headers(a.headers),
                       decode_headers(b.headers))
  end

  defp authority_hostport(authority) do
    hostport =
      case String.split(authority, "@", parts: 2) do
        [_userinfo, hostport] -> hostport
        [hostport] -> hostport
      end

    String.downcase(hostport)
  end

  defp downcase_keys(map) when is_map(map) do
    for {k, v} <- Map.to_list(map) do {String.downcase(k), v} end
    |> Map.new()
  end

  defp map_zip(a, b, defaults \\ %{}) when is_map(a) and is_map(b) do
    a = downcase_keys(a)
    b = downcase_keys(b)
    for {k, v1} <- Map.to_list(a) do
      {k, {v1, Map.get(b, k, Map.get(defaults, k, nil))}}
    end ++ for {k, v2} <- Map.to_list(b), not Map.has_key?(a, k) do
      {k, {Map.get(defaults, k, nil), v2}}
    end
  end

  defp equivalent_parameters(a, b, defaults)
      when is_map(a) and is_map(b) do
    map_zip(a, b, defaults) |> Enum.reduce_while(true,
      fn {k, {v1, v2}}, _ ->
        cond do
          v1 == nil and v2 == nil ->
            {:cont, true}
          v1 == nil or v2 == nil ->
            if k in ["user", "ttl", "method", "maddr", "transport"] do
              {:halt, false} 
            else
              {:cont, true}
            end
          String.downcase(v1) == String.downcase(v2) ->
            {:cont, true}
          true ->
            {:halt, false}
        end
      end)
  end

  defp equivalent_headers(a, b) when is_map(a) and is_map(b) do
    map_zip(a, b) |> Enum.reduce_while(true,
      fn {_, {v1, v2}}, _ ->
        cond do
          v1 == nil and v2 == nil ->
            {:cont, true}
          v1 == nil or v2 == nil ->
            {:halt, false} 
          String.downcase(v1) == String.downcase(v2) ->
            {:cont, true}
          true ->
            {:halt, false}
        end
      end)
  end

  @doc """
  Checks whether two SIP-URIs are equivalent, but using more lazy rules.

  ## Examples

      iex> a = Sippet.URI.parse!("sip:atlanta.com;transport=UDP")
      iex> b = Sippet.URI.parse!("sip:atlanta.com:5060")
      iex> Sippet.URI.lazy_equivalent(a, b)
      true

  """
  @spec lazy_equivalent(t, t) :: boolean
  def lazy_equivalent(a, b) do
    quite_similar(a, b,
      if String.downcase(a.scheme) == "sip" do
        %{"transport" => "udp"}
      else
        %{"transport" => "tls"}
      end)
  end
end

defimpl String.Chars, for: Sippet.URI do
  def to_string(%{scheme: scheme, port: port,
                  parameters: parameters,
                  headers: headers} = uri) do
    uri =
      case scheme && Sippet.URI.default_port(scheme) do
        ^port -> %{uri | port: nil}
        _     -> uri
      end

    # Based on http://tools.ietf.org/html/rfc3986#section-5.3
    authority = extract_authority(uri)

    if(scheme, do: scheme <> ":", else: "") <>
      if(authority, do: authority, else: "") <>
      if(parameters, do: parameters, else: "") <>
      if(headers, do: headers, else: "")
  end

  defp extract_authority(%{host: nil, authority: authority}) do
    authority
  end

  defp extract_authority(%{host: host, userinfo: userinfo, port: port}) do
    # According to the grammar at
    # https://tools.ietf.org/html/rfc3986#appendix-A, a "host" can have a colon
    # in it only if it's an IPv6 or "IPvFuture" address), so if there's a colon
    # in the host we can safely surround it with [].
    if(userinfo, do: userinfo <> "@", else: "") <>
      if(String.contains?(host, ":"), do: "[" <> host <> "]", else: host) <>
      if(port, do: ":" <> Integer.to_string(port), else: "")
  end
end
