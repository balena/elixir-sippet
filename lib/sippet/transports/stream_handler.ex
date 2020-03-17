defmodule Sippet.Transports.StreamHandler do
  @moduledoc false

  alias Sippet.{Message, Router}

  require Logger

  defstruct parent: nil,
            ref: nil,
            socket: nil,
            transport: nil,
            proxy_info: nil,
            opts: [],
            buffer: <<>>,
            peer: nil,
            sock: nil,
            cert: nil,
            timer: nil,
            in_state: :idle,
            header: nil,
            clen: 0,
            sippet: nil,
            connection_type: nil

  @type options :: [option]

  @type option ::
          {:connection_type, :client | :server}
          | {:idle_timeout, integer}
          | {:message_timeout, integer}
          | {:linger_timeout, integer}
          | {:inactivity_timeout, integer}
          | {:max_header_length, integer}
          | {:active_n, integer}
          | {:sippet, atom}

  @doc false
  def init(parent, ref, socket, transport, proxy_info, opts) do
    peer = transport.peername(socket)
    sock = transport.sockname(socket)

    cert =
      case transport.name() do
        :ssl ->
          case :ssl.peercert(socket) do
            {:error, :no_peerceert} ->
              {:ok, :undefined}

            cert ->
              cert
          end

        _ ->
          {:ok, :undefined}
      end

    case {peer, sock, cert} do
      {{:ok, peer}, {:ok, sock}, {:ok, cert}} ->
        state = %__MODULE__{
          parent: parent,
          ref: ref,
          socket: socket,
          transport: transport,
          proxy_info: proxy_info,
          opts: opts,
          peer: peer,
          sock: sock,
          cert: cert,
          sippet: Keyword.fetch!(opts, :sippet),
          connection_type: Keyword.fetch!(opts, :connection_type)
        }

        setopts_active(state)

        state
        |> set_timeout(:idle_timeout)
        |> loop()

      {{:error, reason}, _, _} ->
        terminate(
          :undefined,
          {:socket_error, reason, "A socket error occurred when retrieving the peer name."}
        )

      {_, {:error, reason}, _} ->
        terminate(
          :undefined,
          {:socket_error, reason, "A socket error occurred when retrieving the sock name."}
        )

      {_, _, {:error, reason}} ->
        terminate(
          :undefined,
          {:socket_error, reason,
           "A socket error occurred when retrieving the client TLS certificate."}
        )
    end
  end

  defp setopts_active(%{socket: socket, transport: transport, opts: opts}) do
    # the following is used instead of [active: true] to avoid flooding the
    # reading process with socket data messages, at the same time still
    # providing good performance while reading data.
    # See {active, N} option in https://erlang.org/doc/man/inet.html#setopts-2

    n = Keyword.get(opts, :active_n, 100)
    transport.setopts(socket, active: n)
  end

  defp loop(
         %{
           parent: parent,
           socket: socket,
           transport: transport,
           opts: opts,
           buffer: buffer,
           timer: timer_ref
         } = state
       ) do
    messages = transport.messages()

    ok = elem(messages, 0)
    closed = elem(messages, 1)
    error = elem(messages, 2)

    inactivity_timeout = Keyword.get(opts, :inactivity_timeout, 300_000)

    receive do
      # Socket messages
      {^ok, ^socket, data} ->
        parse(<<buffer::binary, data::binary>>, state)

      {^closed, ^socket} ->
        terminate(state, {:socket_error, :closed, "The socket has been closed."})

      {^error, ^socket, reason} ->
        terminate(state, {:socket_error, reason, "An error has occurred on the socket."})

      # Passive
      {passive, ^socket}
      when (tuple_size(messages) >= 4 and passive == elem(messages, 3)) or
             passive in [:tcp_passive, :ssl_passive] ->
        setopts_active(state)
        loop(state)

      # Timeouts
      {:timeout, ^timer_ref, reason} ->
        timeout(state, reason)

      {:timeout, _, _} ->
        loop(state)

      # System messages
      {:EXIT, ^parent, reason} ->
        terminate(state, {:stop, {:exit, reason}, "Parent process terminated."})

      {:system, from, request} ->
        :sys.handle_system_msg(request, from, parent, __MODULE__, [], state)

      # Calls from supervisor module
      {:"$gen_call", from, call} ->
        handle_call(call, from, state)
        loop(state)

      # Unknown messages
      msg ->
        Logger.warn("Received stray message #{inspect(msg)}")
        loop(state)
    after
      inactivity_timeout ->
        terminate(state, {:socket_error, :timeout, "No message or data received before timeout."})
    end
  end

  defp set_timeout(%{opts: opts} = state, name) do
    state = cancel_timeout(state)

    default =
      case name do
        :message_timeout -> 5000
        :idle_timeout -> 60000
      end

    timeout = Keyword.get(opts, name, default)

    timer_ref =
      case timeout do
        :infinity -> :undefined
        timeout -> Process.send_after(self(), name, timeout)
      end

    %{state | timer: timer_ref}
  end

  defp cancel_timeout(%{timer: timer_ref} = state) do
    :ok =
      case timer_ref do
        :undefined ->
          :ok

        _ ->
          # Do a synchronous cancel and remove the message if any
          # to avoid receiving stray messages.
          if is_reference(timer_ref) do
            Process.cancel_timer(timer_ref)
          end

          receive do
            {:timeout, _timer_ref, _} -> :ok
          after
            0 ->
              :ok
          end
      end

    %{state | timer: :undefined}
  end

  defp timeout(state, :idle_timeout) do
    terminate(
      state,
      {:connection_error, :timeout, "Connection idle."}
    )
  end

  defp timeout(state, :message_timeout) do
    terminate(
      state,
      {:connection_error, :timeout, "Timeout receiving message."}
    )
  end

  defp parse(<<>>, state), do: loop(%{state | buffer: <<>>})

  defp parse(
         <<keep_alive, rest::binary>>,
         %{
           in_state: :idle,
           transport: transport,
           socket: socket,
           connection_type: connection_type
         } = state
       )
       when keep_alive in ["\n", "\r\n"] do
    if connection_type == :server do
      # When remote sends CRLF (or just LF) ping, the idle timer is reset and an
      # pong is sent back
      transport.send(socket, keep_alive)
    end

    state
    |> set_timeout(:idle_timeout)
    |> parse(rest)
  end

  defp parse(buffer, %{in_state: :idle} = state) do
    state = set_timeout(state, :message_timeout)
    parse(buffer, %{state | in_state: :read_header})
  end

  defp parse(buffer, %{in_state: :read_header} = state) do
    case Regex.split(~r/\n\n|\r\n\r\n/, buffer, parts: 2, include_captures: true) do
      [incomplete_header] ->
        loop(%{state | buffer: incomplete_header})

      [header, sep, body] ->
        case Regex.run(~r/(Content-Length|l)[[:space:]]*:[[:space:]]*([0-9]+)/u, header,
               captures: :first
             ) do
          [_, _, length] ->
            clen = length |> String.to_integer()
            parse(body, %{state | in_state: :read_body, header: header <> sep, clen: clen})

          nil ->
            terminate(
              state,
              {:connection_error, :protocol_error, "No Content-Length in message."}
            )
        end
    end
  end

  defp parse(
         buffer,
         %{in_state: :read_body, clen: clen} = state
       ) do
    if byte_size(buffer) < clen do
      loop(%{state | buffer: buffer})
    else
      after_parse(parse_body(buffer, state))
    end
  end

  defp parse_body(
         buffer,
         %{
           clen: clen,
           header: header,
           peer: {peer_ip, peer_port},
           transport: transport,
           sippet: sippet
         } = state
       ) do
    <<body::binary-size(clen), rest::binary>> = buffer
    message = header <> body

    Router.handle_transport_message(sippet, message, {protocol(transport), peer_ip, peer_port})

    %{state | buffer: rest}
  end

  defp after_parse(%{buffer: buffer} = state) do
    state = set_timeout(state, :idle_timeout)
    parse(buffer, %{state | in_state: :idle})
  end

  defp terminate(:undefined, reason), do: exit({:shutdown, reason})

  defp terminate(%{} = state, reason) do
    terminate_linger(state)
    exit({:shutdown, reason})
  end

  defp terminate_linger(%{socket: socket, transport: transport, opts: opts} = state) do
    case transport.shutdown(socket, :write) do
      :ok ->
        case Keyword.get(opts, :linger_timeout, 1000) do
          0 ->
            :ok

          :infinity ->
            terminate_linger_before_loop(state, :undefined, transport.messages())

          timeout ->
            timer_ref = Process.send_after(self(), :linger_timeout, timeout)
            terminate_linger_before_loop(state, timer_ref, transport.messages())
        end

      {:error, _} ->
        :ok
    end
  end

  defp terminate_linger_before_loop(state, timer_ref, messages) do
    # We may already be in active mode when we do this but it's OK because we
    # are shutting down anyway.
    case setopts_active(state) do
      :ok ->
        terminate_linger_loop(state, timer_ref, messages)

      {:error, _} ->
        :ok
    end
  end

  defp terminate_linger_loop(%{socket: socket} = state, timer_ref, messages) do
    ok = elem(messages, 0)
    closed = elem(messages, 1)
    error = elem(messages, 2)

    receive do
      {^ok, ^socket, _} ->
        terminate_linger_loop(state, timer_ref, messages)

      {^closed, ^socket} ->
        :ok

      {^error, ^socket, _} ->
        :ok
  
      {passive, ^socket}
      when (tuple_size(messages) >= 4 and passive == elem(messages, 3)) or
             passive in [:tcp_passive, :ssl_passive] ->
        terminate_linger_before_loop(state, timer_ref, messages)

      {:timeout, _timer_ref, :linger_timeout} ->
        :ok

      _ ->
        terminate_linger_loop(state, timer_ref, messages)
    end
  end

  # System callbacks

  def system_continue(_, _, state), do: loop(state)

  def system_terminate(reason, _, _, state),
    do: terminate(state, {:stop, {:exit, reason}, "sys:terminate/2,3 was called."})

  def system_code_change(misc, _, _, _), do: {:ok, misc}

  # Stack callbacks

  defp handle_call(
         {:send_message, message, key},
         {from, tag},
         %{
           socket: socket,
           transport: transport,
           peer: {peer_ip, peer_port},
           sippet: sippet
         } = state
       ) do
    Logger.debug([
      "sending message to #{stringify(peer_ip, peer_port, transport)}",
      ", #{inspect(key)}"
    ])

    case transport.send(socket, Message.to_iodata(message)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warn([
          "#{protocol(transport)} transport error for",
          " #{stringify(peer_ip, peer_port)}: #{inspect(reason)}"
        ])

        if key != nil do
          Router.receive_transport_error(sippet, key, reason)
        end
    end

    send(from, {tag, :ok})

    case state do
      %{in_state: :idle} ->
        set_timeout(state, :idle_timeout)

      _ ->
        state
    end
  end

  defp stringify(ip, port) do
    address =
      ip
      |> :inet_parse.ntoa()
      |> to_string()

    "#{address}:#{port}"
  end

  defp stringify(ip, port, transport) do
    "#{stringify(ip, port)}/#{protocol(transport)}"
  end

  defp protocol(transport) do
    case transport.name() do
      :ssl -> :tls
      other -> other
    end
  end
end
