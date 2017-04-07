defmodule Sippet.Transaction.Client.State do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine

  @type request :: %Message{start_line: %RequestLine{}}

  @type name :: %Sippet.Transaction.Client{}

  @type t :: [
    request: request,
    name: name,
    extras: %{}
  ]

  defstruct [
    request: nil,
    name: nil,
    extras: %{}
  ]

  @spec new(request, name) :: t
  def new(request, name) do
    %__MODULE__{request: request, name: name}
  end
end
