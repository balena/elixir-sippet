defmodule Sippet.Transports.UDP do
  @moduledoc """
  Implements an UDP transport.

  The UDP transport consists basically in a single listening and sending
  process, this implementation itself.

  This process creates an UDP socket and keeps listening for datagrams in
  active mode. Its job is to forward the datagrams to the processing receiver
  defined in `Sippet.Transports.Receiver`.
  """

  use GenServer

  alias Sippet.Message

  require Logger

  defstruct socket: nil,
            address: nil,
            family: :inet,
            port: 0,
            sippet: nil

  @doc """
  Send a message.

  This function isn't used by the stack, it is provided as a facility function
  case you need to send a message directly through the UDP socket.
  """
  def send_message(message, host, port, key) do
    case Process.whereis(__MODULE__) do
      nil ->
        raise RuntimeError, message: "#{inspect(__MODULE__)} was not started"

      pid ->
        send(pid, {:send_message, message, host, port, key})
    end
  end

  @doc """
  Starts the UDP transport.
  """
  def start_link(args) when is_list(args) do
    if not Keyword.has_key?(args, :sippet) do
      raise ArgumentError, message: "missing the sippet argument"
    end

    args =
      args
      |> Enum.flat_map(fn
        {:port, port} ->
          parse_port(port)

        {:address, address} ->
          parse_address(address)

        {:sippet, _} = tuple -> tuple
      end)

    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  defp parse_port(port) when port > 0 do
    [port: port]
  end

  defp parse_address(address) when is_binary(address),
    do: parse_address({address, :inet})

  defp parse_address({family, address})
       when family in [:inet, :inet6] and is_binary(address) do
    case resolve_name(address, family) do
      {:ok, ip} ->
        [sock_opts: [{:ip, ip}, family]]

      {:error, reason} ->
        raise ArgumentError, message: "address error #{inspect(reason)}"
    end
  end

  defp resolve_name(host, family) do
    host
    |> String.to_charlist()
    |> :inet.getaddr(family)
  end

  @impl true
  def init(args) do
    Sippet.register_transport(:udp, false)

    {:ok, nil, {:continue, args}}
  end

  @impl true
  def handle_continue(args, nil) do
    port = Keyword.get(args, :port, 5060)
    opts = [:binary, {:active, true}] ++ Keyword.get(args, :sock_opts, [])

    case :gen_udp.open(port, opts) do
      {:ok, socket} ->
        {:ok, {address, _port}} = :inet.sockname(socket)

        Logger.info(
          "#{inspect(self())} started transport " <>
            "#{:inet.ntoa(address)}:#{port}/udp"
        )

        state = %__MODULE__{
          socket: socket,
          address: address,
          family: if(:inet6 in opts, do: :inet6, else: :inet),
          port: port,
          sippet: args[:sippet]
        }

        {:noreply, state}

      {:error, reason} ->
        Logger.error(
          "#{inspect(self())} port #{port}/udp " <>
            "#{inspect(reason)}, retrying in 10s..."
        )

        Process.sleep(10_000)

        {:noreply, nil, {:continue, args}}
    end
  end

  @impl true
  def handle_info({:udp, _socket, ip, from_port, packet}, %{sippet: sippet} = state) do
    Sippet.handle_transport_message(sippet, packet, {:udp, ip, from_port})

    {:noreply, state}
  end

  def handle_info(
        {:send_message, message, host, port, key},
        %{socket: socket, family: family, sippet: sippet} = state
      ) do
    with {:ok, ip} <- resolve_name(host, family),
         iodata <- Message.to_iodata(message),
         :ok <- :gen_udp.send(socket, {ip, port}, iodata) do
      :ok
    else
      {:error, reason} ->
        Logger.warn(fn ->
          "#{inspect(self())} udp transport error for " <>
            "#{host}:#{port}: #{inspect(reason)}"
        end)

        if key != nil do
          send(sippet, {:receive_transport_error, key, reason})
        end
    end

    {:noreply, state}
  end

  @impl true
  def terminate(reason, {socket, address, port}) do
    Logger.info(
      "#{inspect(self())} stopped transport " <>
        "#{:inet.ntoa(address)}:#{port}/udp, " <>
        "reason: #{inspect(reason)}"
    )

    :ok = :gen_udp.close(socket)
  end
end
