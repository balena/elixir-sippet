defmodule Sippet.Proxy do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine
  alias Sippet.URI, as: URI
  alias Sippet.Transactions, as: Transactions
  alias Sippet.Transports, as: Transport

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
        %{"lr" => nil}
      else
        hop.parameters |> Map.put("lr", nil)
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
      if branch |> String.starts_with?("z9hG4bK") do
        branch
      else
        "z9hG4bK" <> branch
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
  @spec forward_request(Message.request) ::
      :ok |
      {:ok, client_transaction :: Sippet.Transactions.Client.t} |
      {:error, reason :: term}
  def forward_request(%Message{start_line: %RequestLine{}} = request) do
    if request.start_line.method == :ack do
      request
      |> Transport.send_message()
    else
      request
      |> do_add_max_forwards()
      |> Transactions.send_request()
    end
  end

  defp do_add_max_forwards(message) do
    if message.headers |> Map.has_key?(:max_forwards) do
      %{message | headers: %{message.headers | max_forwards:
          message.headers.max_forwards - 1}}
    else
      %{message | headers: message.headers |> Map.put(:max_forwards, 70)}
    end
  end

  @doc """
  Forwards the request to a given `request_uri`.

  If the method is `:ack`, the request will be sent directly to the network transport.
  Otherwise, a new client transaction will be created.

  This function will override the start line `request_uri` with the supplied one.
  """
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
  def forward_response(%Message{start_line: %StatusLine{}} = response) do
    response =
      response |> Message.update_header(:via, [],
          fn [_ | t] -> t end)

    if response.headers.via == [] do
      raise ArgumentError, "Via cannot be empty, wrong response forward"
    end

    case Transactions.send_response(response) do
      {:error, :no_transaction} ->
        response |> Transport.send_message()
      other ->
        other
    end
  end
end
