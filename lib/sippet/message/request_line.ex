defmodule Sippet.RequestLine do
  alias Sippet.URI, as: URI

  defstruct [
    method: nil,
    request_uri: nil
  ]

  def build(method, %URI{} = request_uri),
    do: %__MODULE__{
      method: method,
      request_uri: request_uri}
  
  def build(method, request_uri)
    when is_binary(request_uri),
    do: %__MODULE__{
      method: method,
      request_uri: URI.parse(request_uri)}
end