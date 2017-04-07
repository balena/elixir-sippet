defmodule Sippet.Transaction do
  defdelegate receive_message(message),
    to: Sippet.Transaction.Registry
  
  defdelegate send_request(request),
    to: Sippet.Transaction.Registry
  
  defdelegate send_response(server_transaction, response),
    to: Sippet.Transaction.Registry

  defdelegate receive_error(transaction, reason),
    to: Sippet.Transaction.Registry
end
