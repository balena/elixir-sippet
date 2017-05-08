defmodule Sippet.Transactions.Client.Key do
  @moduledoc """
  Defines a key in which client transactions are uniquely identified.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  @typedoc "The topmost Via header branch parameter"
  @type branch :: binary

  @type t :: %__MODULE__{
    branch: binary,
    method: Message.method
  }

  defstruct [
    branch: nil,
    method: nil
  ]

  @doc """
  Create a client transaction identifier.
  """
  @spec new(branch, Message.method) :: t
  def new(branch, method)
      when is_binary(method) or is_atom(method) do
    %__MODULE__{branch: branch, method: method}
  end

  @doc """
  Create a client transaction identifier from an outgoing request or an
  incoming response. If they are related, they will be equal.
  """
  @spec new(Message.t) :: t
  def new(%Message{start_line: %RequestLine{}} = outgoing_request) do
    method = outgoing_request.start_line.method

    # Take the topmost via branch
    {_version, _protocol, _sent_by, %{"branch" => branch}} =
      hd(outgoing_request.headers.via)

    new(branch, method)
  end

  def new(%Message{start_line: %StatusLine{}} = incoming_response) do
    {_sequence, method} = incoming_response.headers.cseq

    # Take the topmost via branch
    {_version, _protocol, _sent_by, %{"branch" => branch}} =
      hd(incoming_response.headers.via)

    new(branch, method)
  end

  ## Helpers

  defimpl String.Chars do
    def to_string(%{branch: branch, method: method}),
      do: "#{branch}:#{method}"
  end

  defimpl Inspect do
    def inspect(%{branch: branch, method: method}, _),
      do: "~K[#{branch}|#{inspect method}]"
  end
end
