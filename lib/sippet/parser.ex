defmodule Sippet.Parser do
  @moduledoc """
  Parses the SIP header.
  """

  alias Sippet.{URI, Message}
  alias Sippet.Message.{RequestLine, StatusLine}

  @wsp ~c[ \t]
  @digits ~c[0123456789]

  @known_headers [
    {"accept", :accept, &Sippet.Parser.parse_multiple_type_subtype_params/1}
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
         method: "INVITE",
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

  defp parse_method(" " <> rest, method), do: {:ok, method, rest}

  defp parse_method(<<c, rest::binary>>, method),
    do: parse_method(rest, <<method::binary, c>>)

  defp parse_uri(input), do: parse_uri(input, "")

  defp parse_uri(<<>>, ""), do: {:error, :enouri}

  defp parse_uri(<<>>, _), do: {:error, :enosp}

  defp parse_uri(" " <> rest, uri) do
    with {:ok, uri} <- URI.parse(uri) do
      {:ok, uri, rest}
    end
  end

  defp parse_uri(<<c, rest::binary>>, uri),
    do: parse_uri(rest, <<uri::binary, c>>)

  defp parse_sip_version("SIP/" <> input), do: parse_version(input)

  defp parse_sip_version(_), do: {:error, :ebadver}

  defp parse_version(input), do: parse_version(input, [0])

  defp parse_version(<<>>, [_, _] = v) do
    {:ok, Enum.reverse(v) |> List.to_tuple(), ""}
  end

  defp parse_version(<<>>, _), do: {:error, :ebadver}

  defp parse_version("." <> _, [0]), do: {:error, :ebadver}

  defp parse_version("." <> rest, [major]),
    do: parse_version(rest, [0, major])

  defp parse_version("." <> _, _), do: {:error, :ebadver}

  defp parse_version(<<n, rest::binary>>, [last | v])
       when n in @digits do
    parse_version(rest, [last * 10 + (n - ?0) | v])
  end

  defp parse_version(" " <> rest, [_major, _minor] = v),
    do: {:ok, Enum.reverse(v) |> List.to_tuple(), rest}

  defp parse_version(_, _), do: {:error, :ebadver}

  defp parse_status_code(input), do: parse_status_code(input, 0)

  defp parse_status_code(<<>>, code)
       when code <= 699 and code >= 100 do
    {:ok, code, ""}
  end

  defp parse_status_code(<<>>, _), do: {:error, :ebadcode}

  defp parse_status_code(" " <> rest, code)
       when code <= 699 and code >= 100 do
    {:ok, code, rest}
  end

  defp parse_status_code(" " <> _, _), do: {:error, :ebadcode}

  defp parse_status_code(<<n, rest::binary>>, code)
       when n in @digits do
    parse_status_code(rest, code * 10 + (n - ?0))
  end

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
end
