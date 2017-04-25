defmodule Sippet.Transactions.Server.State do
  @moduledoc """
  Defines the state data used in all server transaction types.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Transactions, as: Transactions

  @typedoc "The server transaction key"
  @type key :: Transactions.Server.Key.t

  @type t :: [
    request: Message.request,
    key: key,
    extras: %{}
  ]

  defstruct [
    request: nil,
    key: nil,
    extras: %{}
  ]

  @doc """
  Creates the server transaction state.
  """
  def new(%Message{start_line: %RequestLine{}} = incoming_request,
          %Transactions.Server.Key{} = key) do
    %__MODULE__{
      request: incoming_request,
      key: key
    }
  end
end
