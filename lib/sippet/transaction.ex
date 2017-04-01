defprotocol Sippet.ClientTransaction do
  def on_response(transaction, message)
  def on_error(transaction, atom)
end

defprotocol Sippet.ServerTransaction do
  def send_response(transaction, message)
  def on_request(transaction, message)
  def on_error(transaction, atom)
end

defprotocol Sippet.ClientTransaction.User do
  def on_response(user, response)
  def on_error(user, reason)
end

defprotocol Sippet.ServerTransaction.User do
  def on_request(user, request)
  def on_error(user, reason)
end
