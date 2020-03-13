defmodule Sippet.Transports.TCP do
  @moduledoc """
  Implements a TCP transport based on `ranch`.
  """

  def child_spec(options) when is_list(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, options}
    }
  end

  @doc """
  Starts the TCP transport.
  """
  def start_link(options) do
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

    max_connections =
      options
      |> Keyword.get(:max_connections, 1024)

    num_acceptors =
      options
      |> Keyword.get(:num_acceptors, 10)

    ref = :"#{name}_listener"

    trans_opts = [
      port: port,
      ip: ip,
      max_connections: max_connections,
      num_acceptors: num_acceptors
    ]

    proto_opts = [
      sippet: name,
      protocol: :tcp,
      connection_type: :server
    ]

    :ranch.start_listener(ref, :ranch_tcp, trans_opts, Sippet.Transports.TCP.Handler, proto_opts)
  end

  defp resolve_name(host, family) do
    host
    |> String.to_charlist()
    |> :inet.getaddr(family)
  end
end
