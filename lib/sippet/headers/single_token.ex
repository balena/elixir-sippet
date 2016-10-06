defmodule Sippet.Headers.SingleToken do
  @behaviour Sippet.Header

  defstruct [
    value: nil
  ]

  @type t :: %__MODULE__{
    value: String.t
  }

  def from_string(string) do
    {token, _} = Sippet.Parser.parse_token(string)
    %__MODULE__{value: token}
  end

  defdelegate to_string(value), to: String.Chars.Sippet.Headers.SingleToken
end

defimpl String.Chars, for: Sippet.Headers.SingleToken do
  def to_string(%Sippet.Headers.SingleToken{} = header) do
    header.value
  end
end
