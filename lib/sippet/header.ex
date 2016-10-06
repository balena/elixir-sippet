defmodule Sippet.Header do
  @callback from_string(String.t) :: any
  @callback to_string(any) :: String.t
end
