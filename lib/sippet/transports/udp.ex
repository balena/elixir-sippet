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
            family: :inet,
            sippet: nil

  @doc """
  Starts the UDP transport.
  """
  def start_link(options) when is_list(options) do
    name =
      case Keyword.fetch(options, :name) do
        {:ok, name} when is_atom(name) ->
          name

        {:ok, other} ->
          raise ArgumentError, "expected :name to be an atom, got: #{inspect(other)}"

        :error ->
          raise ArgumentError, "expected :name option to be present"
      end

    port =
      case Keyword.fetch(options, :port) do
        {:ok, port} when is_integer(port) and port > 0 and port < 65536 ->
          port

        {:ok, other} ->
          raise ArgumentError,
                "expected :port to be an integer between 1 and 65535, got: #{inspect(other)}"

        :error ->
          5060
      end

    {address, family} =
      case Keyword.fetch(options, :address) do
        {:ok, {address, family}} when family in [:inet, :inet6] and is_binary(address) ->
          {address, family}

        {:ok, address} when is_binary(address) ->
          {address, :inet}

        {:ok, other} ->
          raise ArgumentError,
                "expected :address to be an address or {address, family} tuple, got: " <>
                  "#{inspect(other)}"

        :error ->
          {"0.0.0.0", :inet}
      end

    ip =
      case resolve_name(address, family) do
        {:ok, ip} ->
          ip

        {:error, reason} ->
          raise ArgumentError,
                ":address contains an invalid IP or DNS name, got: #{inspect(reason)}"
      end

    GenServer.start_link(__MODULE__, {name, ip, port, family}, name: __MODULE__)
  end

  @impl true
  def init({name, ip, port, family}) do
    Sippet.register_transport(name, :udp, false)

    {:ok, nil, {:continue, {name, ip, port, family}}}
  end

  @impl true
  def handle_continue({name, ip, port, family}, nil) do
    case :gen_udp.open(port, [:binary, {:active, true}, {:ip, ip}, family]) do
      {:ok, socket} ->
        Logger.debug(
          "#{inspect(self())} started transport " <>
            "#{stringify_sockname(socket)}/udp"
        )

        state = %__MODULE__{
          socket: socket,
          family: family,
          sippet: name
        }

        {:noreply, state}

      {:error, reason} ->
        Logger.error(
          "#{inspect(self())} port #{port}/udp " <>
            "#{inspect(reason)}, retrying in 10s..."
        )

        Process.sleep(10_000)

        {:noreply, nil, {:continue, {name, ip, port, family}}}
    end
  end

  @impl true
  def handle_info({:udp, _socket, from_ip, from_port, packet}, %{sippet: sippet} = state) do
    Sippet.Router.handle_transport_message(sippet, packet, {:udp, from_ip, from_port})

    {:noreply, state}
  end

  @impl true
  def handle_call(
        {:send_message, message, to_host, to_port, key},
        _from,
        %{socket: socket, family: family, sippet: sippet} = state
      ) do
    Logger.debug([
      "sending message to #{stringify_hostport(to_host, to_port)}/udp",
      ", #{inspect(key)}"
    ])

    with {:ok, to_ip} <- resolve_name(to_host, family),
         iodata <- Message.to_iodata(message),
         :ok <- :gen_udp.send(socket, {to_ip, to_port}, iodata) do
      :ok
    else
      {:error, reason} ->
        Logger.warn("udp transport error for #{to_host}:#{to_port}: #{inspect(reason)}")

        if key != nil do
          Sippet.Router.receive_transport_error(sippet, key, reason)
        end
    end

    {:reply, :ok, state}
  end

  @impl true
  def terminate(reason, %{socket: socket}) do
    Logger.debug(
      "stopped transport #{stringify_sockname(socket)}/udp, reason: #{inspect(reason)}"
    )

    :gen_udp.close(socket)
  end

  defp resolve_name(host, family) do
    host
    |> String.to_charlist()
    |> :inet.getaddr(family)
  end

  defp stringify_sockname(socket) do
    {:ok, {ip, port}} = :inet.sockname(socket)

    address =
      ip
      |> :inet_parse.ntoa()
      |> to_string()

    "#{address}:#{port}"
  end

  defp stringify_hostport(host, port) do
    "#{host}:#{port}"
  end
end
