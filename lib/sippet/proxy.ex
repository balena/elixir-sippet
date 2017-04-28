defmodule Sippet.Proxy do
  @moduledoc """
  Defines very basic operations commonly used in SIP Proxies.
  """

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.URI, as: URI
  alias Sippet.Transactions, as: Transactions
  alias Sippet.Transports, as: Transports

  @type on_request_sent ::
      :ok |
      {:ok, client_key :: Transactions.Client.Key.t} |
      {:error, reason :: term} |
      no_return

  @type on_response_sent ::
      :ok |
      {:error, reason :: term} |
      no_return

  @doc """
  Adds a Record-Route header to the request.

  When a proxy wishes to remain on the path of future requests in a dialog
  created by this request (assuming the request creates a dialog), it inserts a
  Record-Route header field value in the request, before forwarding.

  The indicated `hop` parameter should indicate the destination where requests
  and responses in a dialog should pass. The `hop` SIP-URI will get a `"lr"`
  parameter, if it does not have one, and will be placed as the first header
  value.
  """
  @spec add_record_route(Message.request, URI.t) :: Message.request
  def add_record_route(%Message{start_line: %RequestLine{}} = request,
      %URI{} = hop) do
    parameters =
      if hop.parameters == nil do
        ";lr"
      else
        hop.parameters
        |> URI.decode_parameters()
        |> Map.put("lr", nil)
        |> URI.encode_parameters()
      end

    record_route = {"", %{hop | parameters: parameters}, %{}}
    request |> Message.update_header(:record_route, [record_route],
      fn list -> [record_route | list] end)
  end

  @doc """
  Adds a Via header to the request.

  A proxy must insert a Via header field value before the existing request Via
  header field values. A `"branch"` parameter will be randomly computed as
  being a 72-bit random string starting with the magic cookie `"z9hG4bK"`.
  """
  @spec add_via(Message.request, Message.protocol, host :: String.t,
                dport :: integer) :: Message.request
  def add_via(%Message{start_line: %RequestLine{}} = request,
      protocol, host, port) do
    add_via(request, protocol, host, port, Message.create_branch())
  end

  @doc """
  Adds a Via header to the request with a supplied `branch`.

  A proxy must insert a Via header field value before the existing request Via
  header field values. If the `branch` parameter does not start with the magic
  cookie `"z9hG4bK"`, it will be added.
  """
  @spec add_via(Message.request, Message.protocol, host :: String.t,
                dport :: integer, branch :: String.t) :: Message.request
  def add_via(%Message{start_line: %RequestLine{}} = request,
      protocol, host, port, branch) do
    branch =
      if branch |> String.starts_with?(Sippet.Message.magic_cookie) do
        branch
      else
        Sippet.Message.magic_cookie <> branch
      end

    params = %{"branch" => branch}
    new_via = {{2, 0}, protocol, {host, port}, params}
    request |> Message.update_header(:via, [new_via],
      fn list -> [new_via | list] end)
  end

  @doc """
  Forwards the request.
 
  If the method is `:ack`, the request will be sent directly to the network transport.
  Otherwise, a new client transaction will be created.

  This function will honor the start line `request_uri`.
  """
  @spec forward_request(Message.request) :: on_request_sent
  def forward_request(%Message{start_line: %RequestLine{}} = request) do
    if request.start_line.method == :ack do
      request
      |> do_add_max_forwards()
      |> do_add_hash_branch()
      |> Transports.send_message(nil)
    else
      request
      |> do_add_max_forwards()
      |> Transactions.send_request()
    end
  end

  defp do_add_max_forwards(message) do
    if message.headers |> Map.has_key?(:max_forwards) do
      max_fws = message.headers.max_forwards
      if max_fws <= 0 do
        raise ArgumentError, "invalid :max_forwards => #{inspect max_fws}"
      else
        %{message | headers: %{message.headers | max_forwards: max_fws - 1}}
      end
    else
      %{message | headers: message.headers |> Map.put(:max_forwards, 70)}
    end
  end

  defp do_add_hash_branch(message) do
    # When the request is forwarded statelessly, like in the case of ACKs, the
    # branch has to be the same in the case of retransmissions. This way, a
    # RIPEMD-160 HMAC is used to compute a hash derived from the topmost Via
    # header field of the received request.

    # XXX(balena): this stack discards RFC 3261 non compliant messages, so the
    # other hash method which uses different parameters of the message is not
    # implemented here.

    [via1, via2 | rest] = message.headers.via
    {_, _, _, %{"branch" => branch}} = via2
    hash =
      :crypto.hmac(:ripemd160, "sippet", branch)
      |> Base.url_encode64(padding: false)

    branch = Sippet.Message.magic_cookie <> hash
    {version, protocol, sentby, parameters} = via1
    via1 = {version, protocol, sentby, %{parameters | "branch" => branch}}

    headers =
      message.headers
      |> Map.put(:via, [via1, via2 | rest])

    %{message | headers: headers}
  end

  @doc """
  Forwards the request to a given `request_uri`.

  If the method is `:ack`, the request will be sent directly to the network transport.
  Otherwise, a new client transaction will be created.

  This function will override the start line `request_uri` with the supplied one.
  """
  @spec forward_request(Message.request, URI.t) :: on_request_sent
  def forward_request(%Message{start_line: %RequestLine{}} = request,
      %URI{} = request_uri) do
    %{request | start_line: %{request.start_line | request_uri: request_uri}}
    |> forward_request()
  end

  @doc """
  Forwards a response.

  The topmost Via header of the response is removed before forwarding.

  The response will find its way back to an existing server transaction, if one
  exists, or will be sent directly to the network transport otherwise.
  """
  @spec forward_response(Message.response) :: on_response_sent
  def forward_response(%Message{start_line: %StatusLine{}} = response) do
    response
    |> remove_topmost_via()
    |> fallback_to_transport(&Transactions.send_response/1)
  end

  defp remove_topmost_via(message) do
    message =
      message |> Message.update_header(:via, [],
          fn [_ | t] -> t end)

    if message.headers.via == [] do
      raise ArgumentError, "Via cannot be empty, wrong message forward"
    end

    message
  end

  defp fallback_to_transport(message, fun) do
    case fun.(message) do
      {:error, :no_transaction} ->
        message |> Transports.send_message()
      other ->
        other
    end
  end

  @doc """
  Forwards a response using an existing server transaction key.

  See `forward_response/1`.
  """
  @spec forward_response(Message.response, Transactions.Server.Key.t)
                         :: on_response_sent
  def forward_response(%Message{start_line: %StatusLine{}} = response,
                       %Transactions.Server.Key{} = server_key) do
    response
    |> remove_topmost_via()
    |> fallback_to_transport(&Transactions.send_response(&1, server_key))
  end
end
