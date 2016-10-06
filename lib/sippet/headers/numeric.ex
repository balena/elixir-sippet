defmodule Sippet.Headers.Numeric do
  defstruct [
    value: 0
  ]

  @type t :: %__MODULE__{
    value: non_neg_integer
  }
end
