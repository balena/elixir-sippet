defmodule Sippet.Transactions.Server.State do
  @moduledoc false

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Transactions, as: Transactions

  @typedoc "The server transaction key"
  @type key :: Transactions.Server.Key.t()

  @type t :: [
          request: Message.request(),
          key: key,
          sippet: atom,
          extras: %{}
        ]

  defstruct request: nil,
            key: nil,
            sippet: nil,
            extras: %{}

  @doc """
  Creates the server transaction state.
  """
  def new(
        %Message{start_line: %RequestLine{}} = incoming_request,
        %Transactions.Server.Key{} = key,
        sippet
      )
      when is_atom(sippet) do
    %__MODULE__{
      request: incoming_request,
      key: key,
      sippet: sippet
    }
  end
end
