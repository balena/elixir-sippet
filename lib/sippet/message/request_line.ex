defmodule Sippet.Message.RequestLine do
  alias Sippet.URI, as: URI

  defstruct [
    method: nil,
    request_uri: nil,
    version: nil
  ]

  @type t :: %__MODULE__{
    method: atom,
    request_uri: URI.t,
    version: {number, number}
  }

  def build(method, %URI{} = request_uri)
    when is_atom(method),
    do: %__MODULE__{
        method: do_raise_if_unknown_method(method),
        request_uri: request_uri,
        version: {2, 0}}
  
  def build(method, request_uri)
    when is_binary(request_uri)
    when is_atom(method),
    do: build(method, URI.parse(request_uri))

  def build(method, request_uri)
    when is_binary(request_uri)
    when is_binary(method),
    do: build(do_method_to_atom(method), request_uri)

  @known_methods [:ack, :bye, :cancel, :info, :invite, :message,
      :notify, :options, :prack, :publish, :pull, :push, :refer,
      :register, :store, :subscribe, :update]

  defp do_raise_if_unknown_method(method) when is_atom(method) do
    case method in @known_methods do
      true -> method
      false -> raise "unknown method, got: #{inspect(method)}"
    end
  end

  defp do_method_to_atom(method) do
    method
    |> String.downcase()
    |> String.to_atom()
  end

  defdelegate to_string(value), to: String.Chars.Sippet.Message.RequestLine

  def to_iodata(%Sippet.Message.RequestLine{version: {major, minor},
      request_uri: uri, method: method}) do
    [if(is_atom(method), do: String.upcase(Atom.to_string(method)), else: method),
      " ", Sippet.URI.to_string(uri),
      " SIP/", Integer.to_string(major), ".", Integer.to_string(minor)]
  end
end

defimpl String.Chars, for: Sippet.Message.RequestLine do
  def to_string(%Sippet.Message.RequestLine{} = request_line) do
    Sippet.Message.RequestLine.to_iodata(request_line) |> IO.iodata_to_binary
  end
end
