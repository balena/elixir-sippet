defmodule Sippet.Message.RequestLine do
  alias Sippet.URI, as: URI

  defstruct [
    method: nil,
    request_uri: nil,
    version: nil
  ]

  @type t :: %__MODULE__{
    method: atom | binary,
    request_uri: URI.t,
    version: {number, number}
  }

  def build(method, %URI{} = request_uri)
      when is_atom(method) or is_binary(method) do
    %__MODULE__{
      method: method,
      request_uri: request_uri,
      version: {2, 0}
    }
  end

  def build(method, request_uri)
      when is_binary(request_uri) do
    build(method, URI.parse!(request_uri))
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
  alias Sippet.Message.RequestLine, as: RequestLine

  def to_string(%RequestLine{} = request_line) do
    request_line
    |> RequestLine.to_iodata()
    |> IO.iodata_to_binary
  end
end
