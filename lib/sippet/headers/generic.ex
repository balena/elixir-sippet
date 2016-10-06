defmodule Sippet.Headers.Generic do
  defstruct [
    value: nil
  ]

  @type t :: %__MODULE__{
    value: String.t
  }
end
