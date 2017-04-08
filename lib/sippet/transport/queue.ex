defmodule Sippet.Transport.Queue do
  alias Sippet.Message, as: Message
  alias Sippet.Transport.Queue.Pool, as: Pool

  def incoming_datagram(datagram, from) do
    worker = Pool.check_out()
    GenServer.cast(worker, {:incoming_datagram, datagram, from})
  end

  def validate_message(%Message{} = message, from) do
    worker = Pool.check_out()
    GenServer.cast(worker, {:validate_message, message, from})
  end
end
