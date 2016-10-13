defmodule Sippet.Parser do
  @lws ' \t'

  def parse_token(string) do
    [_, rest] = string |> skip(@lws)
    [token, rest] = rest |> skip_not_in(@lws ++ ';')
    if token == "", do: raise "empty value"
    {token, rest}
  end

  def parse_type_subtype(string) do
    [_, rest] = string |> skip(@lws)
    if rest == "" do
      {"", ""} # empty header is OK
    else
      [type, rest] = rest |> skip_not_in(@lws ++ '/')
      if not is_token(type), do: raise "invalid token"
      [_, rest] = rest |> skip_to('/')
      [_, rest] = rest |> skip()
      [_, rest] = rest |> skip(@lws)
      if rest == "", do: raise "missing subtype"
      [subtype, rest] = rest |> skip_not_in(@lws ++ ';')
      if not is_token(type), do: raise "invalid token"
      {{type, subtype}, rest}
    end
  end

  def parse_parameters(string) do
    {_, rest} = string |> skip_to(';')
    do_parse_name_values(%{}, rest, ';')
  end

  defp do_parse_name_values(params, "", _) do
    params
  end

  defp do_parse_name_values(params, string, separator) do
    {_, rest} = string |> skip()
    {name_value, rest} = rest |> skip_to(separator)
    {name, value} = do_parse_param(name_value)
    do_parse_name_values(Map.put(params, name, value), rest, separator)
  end

  defp do_parse_param(name_value) do
    {_, rest} = name_value |> skip(@lws)
    {name, rest} = rest |> skip_not_in(@lws ++ '=')
    name = String.downcase(name) |> String.to_atom()
    value =
      if rest == "" do
        nil
      else
        {_, rest} = rest |> skip_to('=')
        if rest == "", do: raise "invalid parameter"
        {_, rest} = rest |> skip()
        {_, value} = rest |> skip(@lws)
        maybe_result = String.trim(value)
        if maybe_result |> String.starts_with?("\"") do
          unquote_string(maybe_result)
        else
          maybe_result
        end
      end
    {name, value}
  end

  def parse_auth_scheme(string) do
    {_, rest} = string |> skip(@lws)
    if rest == "", do: raise "missing authentication scheme"
    rest |> skip_not_in(@lws)
  end

  def parse_auth_params(string) do
    {_, rest} = string |> skip_to(',')
    do_parse_name_values(%{}, rest, ',')
  end

  def parse_uri(string) do
    {_, rest} = string |> skip_to('<')
    if rest == "", do: raise "invalid uri"
    {_, rest} = rest |> skip()
    {uri, rest} = rest |> skip_to('>')
    if rest == "", do: raise "unclosed '<'"
    {_, rest} = rest |> skip()
    {uri, rest}
  end

  def parse_contact(string) do
  end

  def parse_star(string) do
  end

  def parse_warning(string) do
  end

  def parse_via(string) do
  end

  def skip(string, skip_list) do
    do_skip("", string, skip_list, skip_list)
  end

  defp do_skip(skipped, "", _, _) do
    {skipped, ""}
  end

  defp do_skip(skipped, string, '', _) do
    {skipped, string}
  end

  defp do_skip(skipped, string, [skip_char | skip_rest], skip_list) do
    {first_char, rest} = skip(string)
    case first_char == <<skip_char>> do
      false -> do_skip(skipped, string, skip_rest, skip_list)
      true -> do_skip(skipped <> first_char, rest, skip_list, skip_list)
    end
  end

  def skip_not_in(string, skip_list) do
    do_skip_not_in("", string, skip_list, skip_list)
  end

  defp do_skip_not_in(skipped, "", _, _) do
    {skipped, ""}
  end

  defp do_skip_not_in(skipped, string, '', skip_list) do
    {char, rest} = string |> String.split_at(1)
    do_skip_not_in(skipped <> char, rest, skip_list, skip_list)
  end

  defp do_skip_not_in(skipped, string, [skip_char | skip_rest], skip_list) do
    {first_char, _} = skip(string)
    case first_char == <<skip_char>> do
      true -> {skipped, string}
      false -> do_skip_not_in(skipped, string, skip_rest, skip_list)
    end
  end

  def skip_to(string, [char]) do
    do_skip_to("", string, char)
  end

  defp do_skip_to(skipped, "", _) do
    {skipped, ""}
  end

  defp do_skip_to(skipped, string, char) do
    {first_char, rest} = skip(string)
    case first_char == <<char>> do
      true -> {skipped, string}
      false -> do_skip_to(skipped <> first_char, rest, char)
    end
  end

  def skip("") do
    {"", ""}
  end

  def skip(string) do
    string |> String.split_at(1)
  end

  def is_token("") do
    false
  end

  def is_token(string) do
    do_is_token(string)
  end

  defp do_is_token("") do
    true
  end

  defp do_is_token(<<char :: size(8)>> <> rest) do
    cond do
      char >= 0x80 -> false
      char <= 0x1f -> false
      char == 0x7f -> false
      char in '()<>@,;:\\"/[]?={} \t' -> false
      :otherwise -> do_is_token(rest)
    end
  end

  def quote_string(string) do
    do_quote_string(string, "")
  end

  defp do_quote_string("", escaped) do
    "\"" <> escaped <> "\""
  end

  defp do_quote_string(<<char :: size(8)>> <> rest, escaped) do
    possibly_escaped = case char do
      '"' -> "\\\""
      '\\' -> "\\\\"
      other -> other
    end
    do_quote_string(rest, escaped <> possibly_escaped)
  end

  def unquote_string(<<char :: size(8)>> <> rest) do
    if char != '"', do: raise "invalid quoted-string"
    do_unquote_string(rest, "")
  end

  defp do_unquote_string("\"", unescaped) do
    unescaped
  end

  defp do_unquote_string("", _) do
    raise "quoted-string does not end with '\"'"
  end

  defp do_unquote_string(<<char :: size(8)>> <> rest, unescaped) do
    {possibly_unescaped, rest} =
        if char == '\\' do
          <<unescaped_char :: size(8)>> <> without_next_char = rest
          {unescaped_char, without_next_char}
        else
          {char, rest}
        end
    do_unquote_string(rest, unescaped <> to_string(possibly_unescaped))
  end
end
