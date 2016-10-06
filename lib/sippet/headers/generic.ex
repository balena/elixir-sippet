defmodule Sippet.Headers.Generic do
  @behavior Sippet.Header

  defstruct [
    value: nil
  ]

  @type t :: %__MODULE__{
    value: String.t
  }

  def from_string(string) do
    %__MODULE__{value: string}
  end

  defdelegate to_string(value), to: String.Chars.Sippet.Headers.Generic
end

defimpl String.Chars, for: Sippet.Headers.Generic do
  def to_string(%Sippet.Headers.Generic{} = header) do
    header.value
  end
end
