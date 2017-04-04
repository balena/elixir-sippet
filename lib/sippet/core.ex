defprotocol Sippet.Core do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  @type ignore :: term

  @type reason :: atom

  @type incoming_request ::
    %Message{start_line: %RequestLine{}}

  @type incoming_response ::
    %Message{start_line: %StatusLine{}}

  @type client_transaction :: pid

  @type server_transaction :: pid | nil

  @type client_or_server_transaction :: pid

  @doc """
  Receives a new incoming request from a remote host, or ACK.
  """
  @callback on_request(incoming_request, server_transaction) :: ignore

  @doc """
  Receives a response for a sent request.
  """
  @callback on_response(incoming_response, client_transaction) :: ignore

  @doc """
  Sends receives an error from the transaction.
  """
  @callback on_error(reason, client_or_server_transaction) :: ignore
end
