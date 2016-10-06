defmodule Sippet.Headers.Numeric do
  @behavior Sippet.Header

  defstruct [
    value: 0
  ]

  @type t :: %__MODULE__{
    value: non_neg_integer
  }

  def from_string(string) do
    %__MODULE__{value: String.to_integer(string)}
  end

  defdelegate to_string(value), to: String.Chars.Sippet.Headers.Numeric
end

defimpl String.Chars, for: Sippet.Headers.Numeric do
  def to_string(%Sippet.Headers.Numeric{} = header) do
    Integer.to_string(header.value)
  end
end
