defmodule Sippet.Transport do
  defdelegate start_link(), to: Sippet.Transport.Supervisor
end
