defmodule Sippet.Transport.Plug do
  @moduledoc """
  A behaviour module for implementing a listening socket.
  """

  @doc """
  Invoked to start listening for datagrams or connections.
  """
  @callback start_link() :: GenServer.on_start

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Sippet.Transport.Plug
    end
  end
end
