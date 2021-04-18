defmodule ParserTest do
  use ExUnit.Case, async: true
  doctest Sippet.Parser

  @test_first_line [
    {"SIP/ 200 OK", {:error, :ebadver}},
    {"SIP/2.0.1 200 OK", {:error, :ebadver}},
    {"SIP/2 200 OK", {:error, :ebadver}},
    {"SIP/2 .0 200 OK", {:error, :ebadver}},
    {"SIP/2.0a 200 OK", {:error, :ebadver}},
    {"INVITE sip:foo@bar.com SIP/2", {:error, :ebadver}},
    {"INVITE sip:foo@bar.com SIP/2.0.1", {:error, :ebadver}},
    {"INVITE sip:foo@bar.com SIP/", {:error, :ebadver}},
    {"INVITE sip:foo@bar.com SIP/two", {:error, :ebadver}},
    {"INVITE sip:foo@bar.com SIP/2.zero", {:error, :ebadver}},
    {"INVITE SIP/2.0", {:error, :enosp}},
    {"INVITE", {:error, :enosp}},
    {"SIP/2.0200 OK", {:error, :ebadcode}},
    {"SIP/2.0 99 OK", {:error, :ebadcode}}
  ]

  @test_split_lines [
    {"", {[], ""}},
    {"Foo: bar\nFoo: qux", {["Foo: bar", "Foo: qux"], ""}},
    {"Foo: bar\n qux", {["Foo: bar qux"], ""}},
    {"Foo: bar\n\tqux", {["Foo: bar\tqux"], ""}},
    {"Foo: bar\nBar:\n\n", {["Foo: bar", "Bar:"], ""}},
    {"Foo: bar\r\nBar:\n\n", {["Foo: bar", "Bar:"], ""}},
  ]

  for {input, expected} <- @test_first_line do
    @tag input: input
    @tag expected: expected
    test "parse #{inspect(input)} -> #{inspect(expected)}", %{
        input: input,
        expected: expected
    } do
      assert ^expected = Sippet.Parser.parse_first_line(input)
    end
  end

  for {input, expected} <- @test_split_lines do
    @tag input: input
    @tag expected: expected
    test "split lines in #{inspect(input)} -> #{inspect(expected)}", %{
      input: input,
      expected: expected
    } do
      assert ^expected = Sippet.Parser.split_lines(input)
    end
  end
end
