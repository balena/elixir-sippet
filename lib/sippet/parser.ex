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
    if rest == "" do
      %{}
    else
      do_parse_parameters(%{}, rest)
    end
  end

  defp do_parse_parameters(params, "") do
    params
  end

  defp do_parse_parameters(params, string) do
    {_, rest} = string |> skip()
    {name_value, rest} = rest |> skip_to(';')
    {name, value} = do_parse_param(name_value)
    do_parse_parameters(Map.put(params, name, value), rest)
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
        String.trim(value)
        # TODO(balena): unquote value
      end
    {name, value}
  end

  def parse_auth_scheme(string) do
  end

  def parse_auth_params(string) do
  end

  def parse_uri(string) do
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

  def do_is_token("") do
    true
  end

  def do_is_token(string) do
    <<char :: size(8)>> <> rest = string
    cond do
      char >= 0x80 -> false
      char <= 0x1f -> false
      char == 0x7f -> false
      char in '()<>@,;:\\"/[]?={} \t' -> false
      :otherwise -> do_is_token(rest)
    end
  end
end
