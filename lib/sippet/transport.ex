defmodule Sippet.Transport do
  defdelegate start_link(), to: Sippet.Transport.Supervisor
  defdelegate send_message(transaction, message), to: Sippet.Transport.Registry
  defdelegate reliable?(message), to: Sippet.Transport.Registry
end
