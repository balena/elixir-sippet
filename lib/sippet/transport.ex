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

defimpl Sippet.Transport, for: [Any, List, BitString, Integer, Float, Atom, Function, PID, Port, Reference, Tuple, Map] do
  def send(_transport, _message), do: :erlang.error(:not_implemented)
  def reliable(_transport), do: :erlang.error(:not_implemented)
end
