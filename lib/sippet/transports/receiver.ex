defmodule Sippet.Transports.Receiver do
  @moduledoc """
  The transport receiver receives messages from network transports, validates
  and routes them to the transaction module.
  """

  alias Sippet.{Message, Transactions}
  alias Sippet.Message.{RequestLine, StatusLine}

  require Logger

  @type from :: {
          protocol :: atom | binary,
          host :: :inet.ip_address() | binary,
          dport :: :inet.port_number()
        }

  @doc """
  Receives a raw (iodata or binary) SIP message and dispatches it.

  The `iodata` is any complete incoming message just received from the
  transport that needs to get parsed and validated before handled by
  transactions or the core.

  The `from` parameter is a tuple containing the protocol, the host name and
  the port of the socket that received the datagram.
  """
  @spec receive_raw(String.t() | list, from, module | pid) :: :ok

  def receive_raw(iodata, from, core) when is_list(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> receive_raw(from, core)
  end

  def receive_raw("", _from, _core), do: :ok

  def receive_raw("\n" <> rest, from, core), do: receive_raw(rest, from, core)

  def receive_raw("\r\n" <> rest, from, core), do: receive_raw(rest, from, core)

  def receive_raw(raw, from, core) do
    with {:ok, message} <- parse_message(raw),
         prepared_message <- update_via(message, from),
         :ok <- Message.validate(prepared_message, from) do
      Transactions.receive_message(prepared_message, core)
    else
      {:error, reason} ->
        Logger.error(fn ->
          {protocol, address, port} = from

          [
            "discarded message from ",
            "#{ip_to_string(address)}:#{port}/#{protocol}: ",
            "#{inspect(reason)}"
          ]
        end)
    end

    :ok
  end

  defp parse_message(packet) do
    case String.split(packet, ~r{\r?\n\r?\n}, parts: 2) do
      [header, body] ->
        parse_message(header, body)

      [header] ->
        parse_message(header, "")
    end
  end

  defp parse_message(header, body) do
    case Message.parse(header) do
      {:ok, message} -> {:ok, %{message | body: body}}
      other -> other
    end
  end

  defp ip_to_string(ip) when is_binary(ip), do: ip
  defp ip_to_string(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()

  defp update_via(%Message{start_line: %RequestLine{}} = request, {_protocol, ip, from_port}) do
    request
    |> Message.update_header_back(:via, fn
      {version, protocol, {via_host, via_port}, params} ->
        host = ip |> ip_to_string()

        params =
          if host != via_host do
            params |> Map.put("received", host)
          else
            params
          end

        params =
          if from_port != via_port do
            params |> Map.put("rport", to_string(from_port))
          else
            params
          end

        {version, protocol, {via_host, via_port}, params}
    end)
  end

  defp update_via(%Message{start_line: %StatusLine{}} = response, _from), do: response
end
