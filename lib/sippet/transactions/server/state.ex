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
          core: module | pid,
          extras: %{}
        ]

  defstruct request: nil,
            key: nil,
            core: nil,
            extras: %{}

  @doc """
  Creates the server transaction state.
  """
  def new(
        %Message{start_line: %RequestLine{}} = incoming_request,
        %Transactions.Server.Key{} = key,
        core
      )
      when is_pid(core) or is_atom(core) do
    %__MODULE__{
      request: incoming_request,
      key: key,
      core: core
    }
  end
end
