defmodule Sippet.Parser do
  @moduledoc """
  Parses the SIP header.
  """

  alias Sippet.URI
  alias Sippet.Message.{RequestLine, StatusLine}

  @doc """
  Parses the first line of a SIP message.

  ## Example:

      iex> Sippet.Parser.parse_first_line("INVITE sip:foo@bar.com SIP/2.0")
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
      }

      iex> Sippet.Parser.parse_first_line("SIP/2.0 200 OK")
      %Sippet.Message.StatusLine{
        version: {2, 0},
        status_code: 200,
        reason_phrase: "OK"
      }
  """
  def parse_first_line("SIP/" <> _ = status_line) do
    with {:ok, version, rest} <- parse_sip_version(status_line),
         {:ok, code, reason_phrase} <- parse_status_code(rest) do
      %StatusLine{
        version: version,
        status_code: code,
        reason_phrase: reason_phrase
      }
    end
  end

  def parse_first_line(request_line) do
    with {:ok, method, rest} <- parse_method(request_line),
         {:ok, uri, sip_version} <- parse_uri(rest),
         {:ok, version, _} <- parse_sip_version(sip_version) do
      %RequestLine{
        method: method,
        request_uri: uri,
        version: version
      }
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
       when n in ~c[0123456789] do
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
       when n in ~c[0123456789] do
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
       when sp in ~c[ \t] do
    split_lines(<<sp, rest::binary>>, line, lines)
  end

  defp split_lines("\r\n" <> rest, line, lines),
    do: split_lines(rest, "", [line | lines])

  defp split_lines("\n\n" <> rest, line, lines),
    do: {[line | lines] |> Enum.reverse(), rest}

  defp split_lines("\n" <> <<sp, rest::binary>>, line, lines)
       when sp in ~c[ \t] do
    split_lines(<<sp, rest::binary>>, line, lines)
  end

  defp split_lines("\n" <> rest, line, lines),
    do: split_lines(rest, "", [line | lines])

  defp split_lines(<<c, rest::binary>>, line, lines),
    do: split_lines(rest, line <> <<c>>, lines)
end
