defmodule Sippet.StatusLine do
  defstruct [
    status_code: nil,
    reason_phrase: nil
  ]

  def build(status_code)
    when is_integer(status_code),
    do: %__MODULE__{
      status_code: status_code}

  def build(status_code, reason_phrase)
    when is_integer(status_code)
    when is_binary(reason_phrase),
    do: %__MODULE__{
      status_code: status_code,
      reason_phrase: reason_phrase}
end