defmodule Sippet.Transactions.Server.Key do
  @moduledoc """
  Defines a key in which server transactions are uniquely identified.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  @typedoc "The topmost Via header branch parameter"
  @type branch :: binary

  @typedoc "The topmost Via header sent-by parameter"
  @type sentby :: {shost :: binary, sport :: integer}

  @type t :: %__MODULE__{
    branch: binary,
    method: Message.method,
    sentby: sentby
  }

  defstruct [
    branch: nil,
    method: nil,
    sentby: nil
  ]

  @doc """
  Creates a server transaction identifier.
  """
  @spec new(branch, Message.method, sentby) :: t
  def new(branch, method, sentby) do
    %__MODULE__{
      branch: branch,
      method: method,
      sentby: sentby
    }
  end

  @doc """
  Creates a server transaction identifier from an incoming request or an
  outgoing response. If they are related, they will be equal.
  """
  @spec new(Message.t) :: t
  def new(%Message{start_line: %RequestLine{}} = incoming_request) do
    method = incoming_request.start_line.method

    # Take the topmost via branch
    {_version, _protocol, sentby, %{"branch" => branch}} =
      hd(incoming_request.headers.via)

    new(branch, method, sentby)
  end

  def new(%Message{start_line: %StatusLine{}} = outgoing_response) do
    {_sequence, method} = outgoing_response.headers.cseq

    # Take the topmost via sent-by and branch
    {_version, _protocol, sentby, %{"branch" => branch}} =
      hd(outgoing_response.headers.via)

    new(branch, method, sentby)
  end

  ## Helpers

  defimpl String.Chars do
    def to_string(%{branch: branch, method: method, sentby: {host, port}}),
      do: "#{branch}:#{method}:#{host}:#{port}"
  end

  defimpl Inspect do
    def inspect(%{branch: branch, method: method, sentby: {host, port}}, _),
      do: "~K[#{branch}|#{inspect method}|#{host}:#{port}]"
  end
end
