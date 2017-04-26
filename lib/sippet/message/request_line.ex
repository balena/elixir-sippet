defmodule Sippet.Message.RequestLine do
  @moduledoc """
  A SIP Request-Line struct, composed by the Method, Request-URI and
  SIP-Version.

  The `start_line` of requests are represented by this struct. The RFC 3261
  represents the Request-Line as:

      Request-Line  =  Method SP Request-URI SP SIP-Version CRLF

  The above `Method` is represented by atoms, when the method is a known one,
  or by binaries, when the method is unknown. Known ones are `:ack`, `:invite`,
  `:register`, `:cancel`, `:message` and all others returned by the function
  `Sippet.Message.known_methods/0`.

  The `Request-URI` is represented by a `Sippet.URI` struct, breaking down the
  SIP-URI in more useful parts for processing.

  The `SIP-Version` is a `{major, minor}` tuple, which assumes the value
  `{2, 0}` in standard implementations.
  """

  alias Sippet.URI, as: URI

  defstruct [
    method: nil,
    request_uri: nil,
    version: nil
  ]

  @type t :: %__MODULE__{
    method: Sippet.Message.method,
    request_uri: URI.t,
    version: {integer, integer}
  }

  @doc """
  Builds a Request-Line struct.
  """
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

  @doc """
  Returns a binary which corresponds to the text representation of the given
  Request-Line.

  It does not includes an ending line CRLF.
  """
  @spec to_string(t) :: binary
  defdelegate to_string(value), to: String.Chars.Sippet.Message.RequestLine

  @doc """
  Returns an iodata which corresponds to the text representation of the given
  Request-Line.

  It does not includes an ending line CRLF.
  """
  @spec to_iodata(t) :: iodata
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
