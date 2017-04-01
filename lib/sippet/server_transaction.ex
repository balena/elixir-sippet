defprotocol Sippet.ServerTransaction.User do
  def on_request(user, request)
  def on_error(user, reason)
end

defmodule Sippet.ServerTransaction do
  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  def start_link(user, %Message{start_line: %StatusLine{}} = response,
      transport) do
    {_sequence, method} = response.headers.cseq
    case method do
      :invite ->
        Invite.start_link(user, response, transport)
      _otherwise ->
        NonInvite.start_link(user, response, transport)
    end
  end

  def send_response(pid, %Message{start_line: %StatusLine{}} = response)
      when is_pid(pid) do
    :gen_statem.cast(pid, {:send_response, response})
  end

  def on_request(pid, %Message{start_line: %RequestLine{}} = request)
      when is_pid(pid) do
    :gen_statem.cast(pid, {:incoming_request, request})
  end

  def on_error(pid, reason) when is_pid(pid) and is_atom(reason) do
    :gen_statem.cast(pid, {:error, reason})
  end
end

defmodule Sippet.ServerTransaction.Invite do
  def start_link(_user, _message, _transport) do
  end
end

defmodule Sippet.ServerTransaction.NonInvite do
  def start_link(_user, _message, _transport) do
  end
end
