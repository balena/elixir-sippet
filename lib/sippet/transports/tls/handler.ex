defmodule Sippet.Transports.TLS.Handler do
  @moduledoc false

  # Ranch 1
  @doc false
  def start_link(ref, _socket, transport, opts),
    do: start_link(ref, transport, opts)

  # Ranch 2
  @doc false
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :connection_process, [self(), ref, transport, opts])
    {:ok, pid}
  end

  def connection_process(parent, ref, transport, opts) do
    proxy_info =
      case Keyword.get(opts, :proxy_header, false) do
        true ->
          {:ok, proxy_info} = :ranch.recv_proxy_header(ref, 1000)
          proxy_info

        false ->
          :undefined
      end

    {:ok, socket} = :ranch.handshake(ref)

    Sippet.Transports.StreamHandler.init(parent, ref, socket, transport, proxy_info, opts)
  end
end
