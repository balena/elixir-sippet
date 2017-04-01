defprotocol Sippet.Transport do
  @doc """
  Sends a message to this transport.
  """
  def send(transport, message)

  @doc """
  Whether this transport is reliable (stream-based).
  """
  def reliable(transport)
end
