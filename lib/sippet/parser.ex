defmodule Sippet.Parser do
  @moduledoc """
  Parses the SIP header.
  """

  alias Sippet.Message
  alias Sippet.Message.{RequestLine, StatusLine}

  @wsp ~c[ \t]
  @digits ~c[0123456789]
  @alpha Enum.map(?a..?z, & &1) ++ Enum.map(?A..?Z, & &1)
  @alphanum @alpha ++ @digits
  @token @alphanum ++ ~c[-.!%*_+`'~]

  @methods %{
    "ACK" => :ack,
    "BYE" => :bye,
    "CANCEL" => :cancel,
    "INFO" => :info,
    "INVITE" => :invite,
    "MESSAGE" => :message,
    "NOTIFY" => :notify,
    "OPTIONS" => :options,
    "PRACK" => :prack,
    "PUBLISH" => :publish,
    "PULL" => :pull,
    "PUSH" => :push,
    "REFER" => :refer,
    "REGISTER" => :register,
    "STORE" => :store,
    "SUBSCRIBE" => :subscribe,
    "UPDATE" => :update
  }

  @known_headers [
    {"accept", :accept, &Sippet.Parser.parse_multiple_type_subtype_params/1},
    {"accept-encoding", :accept_encoding, &Sippet.Parser.parse_multiple_token_params/1},
    {"accept-language", :accept_language, &Sippet.Parser.parse_multiple_token_params/1},
    {"alert-info", :alert_info, &Sippet.Parser.parse_multiple_uri_params/1},
    {"content-type", :content_type, &Sippet.Parser.parse_single_type_subtype_params/1},
    {"call-info", :call_info, &Sippet.Parser.parse_multiple_uri_params/1},
    {"error-info", :error_info, &Sippet.Parser.parse_multiple_uri_params/1},
  ]

  def parse(iodata) when is_list(iodata),
    do: iodata |> IO.iodata_to_binary() |> parse()

  def parse(binary) when is_binary(binary),
    do: binary |> split_lines() |> parse_lines()

  defp parse_lines({[], _}), do: {:error, :ebadmsg}

  defp parse_lines({[first_line | headers], body}) do
    with {:ok, start_line} <- parse_first_line(first_line),
         {:ok, parsed_headers} <- parse_headers(headers) do
      %Message{
        start_line: start_line,
        headers: parsed_headers |> Map.new(),
        body: body
      }
    end
  end

  defp parse_headers(headers), do: parse_headers(headers, [])

  defp parse_headers([], parsed_headers), do: {:ok, parsed_headers}

  defp parse_headers([header_line | headers], acc) do
    with {:ok, header} <- parse_header(header_line) do
      parse_headers(headers, [header | acc])
    end
  end

  defp parse_header(header_line) do
    with {:ok, header_name, header_value} <- split_header(header_line) do
      parse_header_value(header_name, header_value)
    end
  end

  defp split_header(header_line), do: split_header(header_line, "")

  defp split_header(<<>>, _), do: {:error, :ebadheader}

  defp split_header(<<c, header_value::binary>>, header_name) when c in @wsp,
    do: split_header(header_value, header_name)

  defp split_header(":" <> header_value, header_name),
    do: {:ok, header_name |> String.downcase(), header_value}

  defp split_header(<<c, header_value::binary>>, header_name),
    do: split_header(header_value, header_name <> <<c>>)

  for {header_name, header_key, parser} <- @known_headers do
    defp parse_header_value(unquote(header_name), header_value) do
      with {:ok, result} <- unquote(parser).(header_value) do
        {:ok, {unquote(header_key), result}}
      end
    end
  end

  defp parse_header_value(header_name, header_value),
    do: {:ok, {header_name, header_value}}

  @doc """
  Parses the first line of a SIP message.

  ## Example:

      iex> Sippet.Parser.parse_first_line("INVITE sip:foo@bar.com SIP/2.0")
      {:ok,
       %Sippet.Message.RequestLine{
         method: :invite,
         request_uri: %Sippet.URI{
           authority: "foo@bar.com",
           headers: nil,
           host: "bar.com",
           parameters: nil,
           port: 5060,
           scheme: "sip",
           userinfo: "foo"
         },
         version: {2, 0}
       }}

      iex> Sippet.Parser.parse_first_line("SIP/2.0 200 OK")
      {:ok,
       %Sippet.Message.StatusLine{
         version: {2, 0},
         status_code: 200,
         reason_phrase: "OK"
       }}
  """
  def parse_first_line("SIP/" <> _ = status_line) do
    with {:ok, version, rest} <- parse_sip_version(status_line),
         {:ok, code, reason_phrase} <- parse_status_code(rest) do
      {:ok,
       %StatusLine{
         version: version,
         status_code: code,
         reason_phrase: reason_phrase
       }}
    end
  end

  def parse_first_line(request_line) do
    with {:ok, method, rest} <- parse_method(request_line),
         {:ok, uri, sip_version} <- parse_uri(rest),
         {:ok, version, _} <- parse_sip_version(sip_version) do
      {:ok,
       %RequestLine{
         method: method,
         request_uri: uri,
         version: version
       }}
    end
  end

  defp parse_method(input), do: parse_method(input, "")

  defp parse_method(<<>>, ""), do: {:error, :enomethod}

  defp parse_method(<<>>, _), do: {:error, :enosp}

  defp parse_method(<<c, rest::binary>>, method) when c in @wsp,
    do: {:ok, Map.get(@methods, method, method), rest}

  defp parse_method(<<c, rest::binary>>, method),
    do: parse_method(rest, <<method::binary, c>>)

  defp parse_uri(input), do: parse_uri(input, "")

  defp parse_uri(<<>>, ""), do: {:error, :enouri}

  defp parse_uri(<<>>, _), do: {:error, :enosp}

  defp parse_uri(" " <> rest, uri) do
    with {:ok, uri} <- Sippet.URI.parse(uri) do
      {:ok, uri, rest}
    end
  end

  defp parse_uri(<<c, rest::binary>>, uri),
    do: parse_uri(rest, <<uri::binary, c>>)

  defp parse_sip_version("SIP/2.0"), do: {:ok, {2, 0}, <<>>}

  defp parse_sip_version(<<"SIP/2.0", c, rest::binary>>) when c in @wsp,
    do: {:ok, {2, 0}, rest}

  defp parse_sip_version(_), do: {:error, :ebadver}

  defp parse_status_code(input), do: parse_status_code(input, 0)

  defp parse_status_code(<<>>, code) when code in 100..699, do: {:ok, code, ""}

  defp parse_status_code(<<>>, _), do: {:error, :ebadcode}

  defp parse_status_code(<<c, rest::binary>>, code) when c in @wsp and code in 100..699,
    do: {:ok, code, rest}

  defp parse_status_code(<<n, rest::binary>>, code) when n in @digits,
    do: parse_status_code(rest, code * 10 + (n - ?0))

  defp parse_status_code(_, _), do: {:error, :ebadcode}

  @doc """
  Split header lines.

  ## Example:

      iex> Sippet.Parser.split_lines("Foo: bar")
      {["Foo: bar"], ""}

      iex> Sippet.Parser.split_lines("Foo: bar\\r\\nFoo: qux")
      {["Foo: bar", "Foo: qux"], ""}

      iex> Sippet.Parser.split_lines("Foo: bar\\r\\nFoo: qux\\r\\n")
      {["Foo: bar", "Foo: qux"], ""}

      iex> Sippet.Parser.split_lines("Foo: bar\\r\\nFoo: qux\\r\\n\\r\\n")
      {["Foo: bar", "Foo: qux"], ""}

      iex> Sippet.Parser.split_lines("Foo: bar\\r\\nFoo: qux\\r\\n\\r\\nrest")
      {["Foo: bar", "Foo: qux"], "rest"}

      iex> Sippet.Parser.split_lines("Foo: bar\\nFoo: qux\\n\\nrest")
      {["Foo: bar", "Foo: qux"], "rest"}
  """
  def split_lines(input), do: split_lines(input, "", [])

  defp split_lines(<<>>, <<>>, lines), do: {lines |> Enum.reverse(), ""}

  defp split_lines(<<>>, line, lines),
    do: {[line | lines] |> Enum.reverse(), ""}

  defp split_lines("\r\n\r\n" <> rest, line, lines),
    do: {[line | lines] |> Enum.reverse(), rest}

  defp split_lines("\r\n" <> <<sp, rest::binary>>, line, lines)
       when sp in @wsp do
    split_lines(<<sp, rest::binary>>, line, lines)
  end

  defp split_lines("\r\n" <> rest, line, lines),
    do: split_lines(rest, "", [line | lines])

  defp split_lines("\n\n" <> rest, line, lines),
    do: {[line | lines] |> Enum.reverse(), rest}

  defp split_lines("\n" <> <<sp, rest::binary>>, line, lines)
       when sp in @wsp do
    split_lines(<<sp, rest::binary>>, line, lines)
  end

  defp split_lines("\n" <> rest, line, lines),
    do: split_lines(rest, "", [line | lines])

  defp split_lines(<<c, rest::binary>>, line, lines),
    do: split_lines(rest, line <> <<c>>, lines)

  @doc """
  Parse headers such as `Accept`.

  ## Example:

      iex> Sippet.Parser.parse_multiple_type_subtype_params("application/json;q=1")
      {:ok, [{{"application", "json"}, %{"q" => "1"}}]}

      iex> Sippet.Parser.parse_multiple_type_subtype_params("image/png;q=1, image/gif;q=0.9")
      {:ok, [{{"image", "png"}, %{"q" => "1"}}, {{"image", "gif"}, %{"q" => "0.9"}}]}

      iex> Sippet.Parser.parse_multiple_type_subtype_params("")
      {:ok, []}
  """
  def parse_multiple_type_subtype_params(input),
    do: parse_multiple_type_subtype_params(input, "", [])

  defp parse_multiple_type_subtype_params(<<>>, <<>>, list), do: {:ok, list |> Enum.reverse()}

  defp parse_multiple_type_subtype_params(<<>>, part, list) do
    with {:ok, {type_subtype, params}} <- parse_single_type_subtype_params(part) do
      {:ok, [{type_subtype, params} | list] |> Enum.reverse()}
    end
  end

  defp parse_multiple_type_subtype_params("," <> input, part, list) do
    with {:ok, {type_subtype, params}} <- parse_single_type_subtype_params(part) do
      parse_multiple_type_subtype_params(input, "", [{type_subtype, params} | list])
    end
  end

  defp parse_multiple_type_subtype_params(<<c, input::binary>>, part, list),
    do: parse_multiple_type_subtype_params(input, part <> <<c>>, list)

  @doc """
  Parse headers such as `Content-Type`.

  ## Example:

      iex> Sippet.Parser.parse_single_type_subtype_params("application/json;q=1")
      {:ok, {{"application", "json"}, %{"q" => "1"}}}
  """
  def parse_single_type_subtype_params(input),
    do: parse_single_type_subtype_params(input, "", "")

  defp parse_single_type_subtype_params(<<>>, _subtype, ""),
    do: {:error, :ebadtype}

  defp parse_single_type_subtype_params(<<>>, "", _type),
    do: {:error, :ebadtype}

  defp parse_single_type_subtype_params(<<>>, subtype, type),
    do: {:ok, {{type, subtype}, %{}}}

  defp parse_single_type_subtype_params(<<c, input::binary>>, part, type) when c in @wsp,
    do: parse_single_type_subtype_params(input, part, type)

  defp parse_single_type_subtype_params("/" <> input, type, ""),
    do: parse_single_type_subtype_params(input, "", type)

  defp parse_single_type_subtype_params("/" <> _input, _subtype, _type),
    do: {:error, :ebadtype}

  defp parse_single_type_subtype_params(";" <> _input, "", _type),
    do: {:error, :ebadtype}

  defp parse_single_type_subtype_params(";" <> _input, _subtype, ""),
    do: {:error, :ebadtype}

  defp parse_single_type_subtype_params(";" <> input, subtype, type) do
    with {:ok, params} <- parse_params(input) do
      {:ok, {{type, subtype}, params}}
    end
  end

  defp parse_single_type_subtype_params(<<c, input::binary>>, part, type),
    do: parse_single_type_subtype_params(input, part <> <<c>>, type)

  @doc """
  Parse semicolon separated values.

  ## Example:

      iex> Sippet.Parser.parse_params("tag=abc;q=1")
      {:ok, %{"tag" => "abc", "q" => "1"}}
  """
  def parse_params(input), do: parse_params(input, "", "", [])

  defp parse_params(<<>>, "", "", _list),
    do: {:error, :ebadparam}

  defp parse_params(<<>>, key, "", list),
    do: {:ok, [{key, ""} | list] |> Map.new()}

  defp parse_params(<<>>, value, key, list),
    do: {:ok, [{key, value} | list] |> Map.new()}

  defp parse_params(<<c, input::binary>>, part, key, list) when c in @wsp,
    do: parse_params(input, part, key, list)

  defp parse_params("=" <> input, key, "", list),
    do: parse_params(input, "", key, list)

  defp parse_params("=" <> _input, _value, _key, _list),
    do: {:error, :ebadparam}

  defp parse_params(";" <> _input, _value, "", _list),
    do: {:error, :ebadparam}

  defp parse_params(";" <> input, value, key, list),
    do: parse_params(input, "", "", [{key, value} | list])

  defp parse_params(<<c, input::binary>>, part, key, list),
    do: parse_params(input, part <> <<c>>, key, list)

  @doc """
  Parse multiple token followed or not by semicolon separated values.

  ## Examples:

      iex> Sippet.Parser.parse_multiple_token_params("")
      {:ok, []}

      iex> Sippet.Parser.parse_multiple_token_params("a;q=0.9")
      {:ok, [{"a", %{"q" => "0.9"}}]}

      iex> Sippet.Parser.parse_multiple_token_params("a;q=0.9, b;q=0.1")
      {:ok, [{"a", %{"q" => "0.9"}}, {"b", %{"q" => "0.1"}}]}
  """
  def parse_multiple_token_params(input), do: parse_multiple_token_params(input, [])

  defp parse_multiple_token_params(<<>>, list), do: {:ok, Enum.reverse(list)}

  defp parse_multiple_token_params("," <> rest, list),
    do: parse_multiple_token_params(rest, [{<<>>, %{}} | list])

  defp parse_multiple_token_params(";" <> rest, [{token, _} | list]) do
    {params, rest} =
      case String.split(rest, ",", parts: 2) do
        [params] -> {params, <<>>}
        [params, rest] -> {params, "," <> rest}
      end

    with {:ok, parsed_params} <- parse_params(params) do
      parse_multiple_token_params(rest, [{token, parsed_params} | list])
    end
  end

  defp parse_multiple_token_params(<<c, rest::binary>>, list) when c in @wsp,
    do: parse_multiple_token_params(rest, list)

  defp parse_multiple_token_params(<<c, rest::binary>>, []) when c in @token,
    do: parse_multiple_token_params(rest, [{<<c>>, %{}}])

  defp parse_multiple_token_params(<<c, rest::binary>>, [{token, _} | list]) when c in @token,
    do: parse_multiple_token_params(rest, [{token <> <<c>>, %{}} | list])

  defp parse_multiple_token_params(_, _), do: {:error, :ebadtoken}

  @doc """
  Parse multiple URI followed or not by semicolon separated values.

  ## Examples:

      iex> Sippet.Parser.parse_multiple_uri_params("")
      {:ok, []}

      iex> Sippet.Parser.parse_multiple_uri_params("<http://www.example.com/sounds/moo.wav>")
      {:ok,
       [
         {%URI{
           authority: "www.example.com",
           fragment: nil,
           host: "www.example.com",
           path: "/sounds/moo.wav",
           port: 80,
           query: nil,
           scheme: "http",
           userinfo: nil
          }, %{}}
       ]}

      iex> Sippet.Parser.parse_multiple_uri_params("<http://www.example.com/sounds/moo.wav>;q=1.0")
      {:ok,
       [
         {%URI{
           authority: "www.example.com",
           fragment: nil,
           host: "www.example.com",
           path: "/sounds/moo.wav",
           port: 80,
           query: nil,
           scheme: "http",
           userinfo: nil
          }, %{"q" => "1.0"}}
       ]}

      iex> Sippet.Parser.parse_multiple_uri_params("<http://www.example.com/alice/photo.jpg> ;purpose=icon, <http://www.example.com/alice/> ;purpose=info")
      {:ok,
       [
         {
           %URI{
             authority: "www.example.com",
             fragment: nil,
             host: "www.example.com",
             path: "/alice/photo.jpg",
             port: 80,
             query: nil,
             scheme: "http",
             userinfo: nil
           },
           %{"purpose" => "icon"}
         },
         {
           %URI{
             authority: "www.example.com",
             fragment: nil,
             host: "www.example.com",
             path: "/alice/",
             port: 80,
             query: nil,
             scheme: "http",
             userinfo: nil
           }, %{"purpose" => "info"}
         }
       ]}
  """
  def parse_multiple_uri_params(input), do: parse_multiple_uri_params(input, [])

  defp parse_multiple_uri_params(<<>>, []), do: {:ok, []}

  defp parse_multiple_uri_params(<<>>, [{%URI{}, _} | _] = list), do: {:ok, Enum.reverse(list)}

  defp parse_multiple_uri_params(<<>>, _), do: {:error, :ebaduri}

  defp parse_multiple_uri_params("," <> rest, [{%URI{}, _} | _] = list),
    do: parse_multiple_uri_params(rest, [{<<>>, %{}} | list])

  defp parse_multiple_uri_params("," <> _rest, _list), do: {:error, :ebaduri}

  defp parse_multiple_uri_params(";" <> rest, [{%URI{} = uri, _} | list]) do
    {params, rest} =
      case String.split(rest, ",", parts: 2) do
        [params] -> {params, <<>>}
        [params, rest] -> {params, "," <> rest}
      end

    with {:ok, parsed_params} <- parse_params(params) do
      parse_multiple_uri_params(rest, [{uri, parsed_params} | list])
    end
  end

  defp parse_multiple_uri_params(";" <> _rest, _list), do: {:error, :baduri}

  defp parse_multiple_uri_params(<<c, rest::binary>>, list) when c in @wsp,
    do: parse_multiple_uri_params(rest, list)

  defp parse_multiple_uri_params("<" <> rest, []),
    do: parse_multiple_uri_params(rest, [{<<"<">>, %{}}])

  defp parse_multiple_uri_params("<" <> rest, [{<<>>, _} | list]),
    do: parse_multiple_uri_params(rest, [{<<"<">>, %{}} | list])

  defp parse_multiple_uri_params(">" <> rest, [{"<" <> uri, _} | list]) do
    case URI.parse(uri) do
      %URI{scheme: scheme} = parsed_uri when is_binary(scheme) ->
        parse_multiple_uri_params(rest, [{parsed_uri, %{}} | list])

      _ ->
        {:error, :baduri}
    end
  end

  defp parse_multiple_uri_params(<<c, rest::binary>>, [{"<" <> uri, _} | list]),
    do: parse_multiple_uri_params(rest, [{"<" <> uri <> <<c>>, %{}} | list])

  defp parse_multiple_uri_params(_, _), do: {:error, :ebaduri}
end
