defmodule Sippet.Message.RequestLine do
  alias Sippet.URI, as: URI

  defstruct [
    method: nil,
    request_uri: nil
  ]

  @type t :: %__MODULE__{
    method: atom,
    request_uri: URI.t
  }

  def build(method, %URI{} = request_uri)
    when is_atom(method),
    do: %__MODULE__{
        method: do_raise_if_unknown_method(method),
        request_uri: request_uri}
  
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
end
