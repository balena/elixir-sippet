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

  @type client_key :: Transactions.Client.Key.t

  @type request :: Message.request

  @type on_request_sent ::
      {:ok, client_key, request} |
      {:error, reason :: term} |
      no_return

  @type on_request_sent_stateless ::
      {:ok, request} |
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
  cookie `"z9hG4bK"`, one will be added.
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
  Returns a binary representing a textual branch identifier obtained from the
  topmost Via header of the request.

  This derived branch has the property to be the same case the topmost Via
  header of the `request` is also the same, as in the case of retransmissions.

  This operation is usually performed for stateless proxying, like in the case
  of ACK requests, and contains the magic cookie. In order to correctly derive
  the branch, the input `request` must not have been modified after reception.
  """
  @spec derive_branch(request) :: binary
  def derive_branch(%Message{start_line: %RequestLine{}} = request) do
    [{_, _, _, %{"branch" => branch}} | _] = request.headers.via

    input =
      if branch |> String.starts_with?(Message.magic_cookie) do
        branch
      else
        request_uri = URI.to_string(request.start_line.request_uri)
        [{_, protocol, {address, port}, params} | _] = request.headers.via
        {_, _, %{"tag" => from_tag}} = request.headers.from
        call_id = request.headers.call_id
        {sequence, _method} = request.headers.cseq
        to_tag =
          case request.headers.to do
            {_, _, %{"tag" => to_tag}} ->
              to_tag
            _other ->
              ""
          end

        via_params =
          Map.to_list(params)
          |> Enum.reduce([], fn {k, v}, acc -> [k, v | acc] end)

        [request_uri, to_string(protocol), address, to_string(port),
         call_id, from_tag, to_tag, to_string(sequence), via_params]
      end

    hash =
      :crypto.hmac(:ripemd160, "sippet", input)
      |> Base.url_encode64(padding: false)

    Message.magic_cookie <> hash
  end

  @doc """
  Forwards the request statefully.

  The request is sent using a client transaction. If it cannot be sent using
  one, it will raise an exception.

  This function will honor the start line `request_uri`.
  """
  @spec forward_request(Message.request) :: on_request_sent
  def forward_request(%Message{start_line: %RequestLine{}} = request) do
    request =
      request
      |> do_handle_max_forwards()
      |> do_maybe_handle_route()

    case request |> Transactions.send_request() do
      {:ok, client_key} -> {:ok, client_key, request}
      other -> other
    end
  end

  defp do_handle_max_forwards(message) do
    if message |> Message.has_header?(:max_forwards) do
      max_fws = message.headers.max_forwards
      if max_fws <= 0 do
        raise ArgumentError, "invalid :max_forwards => #{inspect max_fws}"
      else
        message |> Message.put_header(:max_forwards, max_fws - 1)
      end
    else
      message |> Message.put_header(:max_forwards, 70)
    end
  end

  defp do_maybe_handle_route(%Message{start_line: %RequestLine{}} = request) do
    {is_strict, target_uri} =
      if request |> Message.has_header?(:route) do
        {_, target_uri, _} = hd(request.headers.route)
        if target_uri.parameters == nil do
          {false, nil}
        else
          case URI.decode_parameters(target_uri.parameters) do
            %{"lr" => _} -> {false, nil}
            _no_lr -> {true, target_uri}
          end
        end
      else
        {false, nil}
      end

    if is_strict do
      # strict-routing requirements
      request_uri = request.start_line.request_uri
      request =
        request
        |> Message.put_header_back(:route, {"", request_uri, %{}})
        |> Message.delete_header_front(:route)
      
      %{request | start_line:
        %{request.start_line | request_uri: target_uri}}
    else
      request  # no change
    end
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
  Forwards the request statelessly.

  The request will be sent directly to the network transport.
  """
  @spec stateless_forward_request(request) :: on_request_sent_stateless
  def stateless_forward_request(
      %Message{start_line: %RequestLine{}} = request) do
    request =
      request
      |> do_handle_max_forwards()
      |> do_maybe_handle_route()

    request |> Transports.send_message(nil)

    {:ok, request}
  end

  @doc """
  Forwards a response.

  You should check and remove the topmost Via before calling this function.

  The response will find its way back to an existing server transaction, if one
  exists, or will be sent directly to the network transport otherwise.
  """
  @spec forward_response(Message.response) :: on_response_sent
  def forward_response(%Message{start_line: %StatusLine{}} = response) do
    response
    |> fallback_to_transport(&Transactions.send_response/1)
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
    |> fallback_to_transport(&Transactions.send_response(&1, server_key))
  end
end
