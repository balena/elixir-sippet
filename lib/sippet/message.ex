defmodule Sippet.Message do
  @moduledoc """
  Message primitive for composing SIP messages.
  Build a SIP message with the `Sippet.Message` struct.

      request =
        Sippet.Message.build_request("INVITE", "sip:joe@example.com")
        |> Sippet.Message.put_new_header(:to,
                Sippet.To.new("sip:joe@example.com"))
        ...
  """

  alias Sippet.URI, as: URI
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Message.StatusLine, as: StatusLine

  defstruct [
    start_line: nil,
    headers: %{},
    body: nil
  ]

  @type uri :: URI.t
  @type method :: String.t
  @type message :: %Sippet.Message{}
  @type header :: atom
  @type value :: struct
  @type t :: %__MODULE__{
    start_line: RequestLine.t | StatusLine.t,
    headers: %{header => [value]},
    body: String.t
  }

  @doc """
  Build a SIP request.
  """
  @spec build_request(method, uri) :: message
  def build_request(method, request_uri),
    do: %Sippet.Message{start_line:
      RequestLine.build(method, request_uri)}

  @doc """
  Build a SIP response.
  """
  @spec build_response(integer, String.t) :: message
  def build_response(response_code, reason_phrase)
    when is_integer(response_code),
    do: %Sippet.Message{start_line:
      StatusLine.build(response_code, reason_phrase)}

  @spec build_response(integer) :: message
  def build_response(response_code)
    when is_integer(response_code),
    do: %Sippet.Message{start_line:
      StatusLine.build(response_code)}

  @doc """
  Shortcut to check if the message is a request.
  """
  @spec request?(message) :: boolean
  def request?(%Sippet.Message{start_line: %RequestLine{}} = _), do: true

  def request?(_), do: false

  @doc """
  Shortcut to check if the message is a response.
  """
  @spec response?(message) :: boolean
  def response?(%Sippet.Message{start_line: %StatusLine{}} = _), do: true

  def response?(_), do: false

  @doc """
  Returns whether a given `header` exists in the given `message`.
  """
  @spec has_header?(message, header) :: boolean
  def has_header?(message, header) do
    Map.has_key?(message.headers, header)
  end

  @doc """
  Puts the `value` under `header` on the `message` unless the `header` already
  exists.
  """
  @spec put_new_header(message, header, value) :: message
  def put_new_header(message, header, value) do
    case has_header?(message, header) do
      true -> message
      false -> %{message | headers: Map.put(message.headers, header, [value])}
    end
  end

  @doc """
  Evaluates `fun` and puts the result under `header` in `message` unless
  `header` is already present.

  This function is useful in case you want to compute the value to put under
  `header` only if `header` is not already present (e.g., the value is
  expensive to calculate or generally difficult to setup and teardown again).
  """
  @spec put_new_lazy_header(message, header, (() -> value)) :: message
  def put_new_lazy_header(message, header, fun) when is_function(fun, 0) do
    case has_header?(message, header) do
      true -> message
      false -> %{message | headers: Map.put(message.headers, header, [fun.()])}
    end
  end

  @doc """
  Puts the `value` under `header` on the `message`, as front element.

  If the parameter `value` is `nil`, then the empty list will be prefixed to
  the `header`.
  """
  @spec put_header_front(message, header, value) :: message
  def put_header_front(message, header, value) do
    existing = get_header(message, header, [])
    new_list = case value do
      nil -> existing
      _ -> [value|existing]
    end
    %{message | headers: Map.put(message.headers, header, new_list)}
  end

  @doc """
  Puts the `value` under `header` on the `message`, as last element.

  If the parameter `value` is `nil`, then the empty list will be appended to
  the `header`.
  """
  @spec put_header_back(message, header, value) :: message
  def put_header_back(message, header, value) do
    existing = get_header(message, header, [])
    new_list = case value do
      nil -> existing
      _ -> List.foldr(existing, [value], fn(x, acc) -> [x|acc] end)
    end
    %{message | headers: Map.put(message.headers, header, new_list)}
  end

  @doc """
  Deletes all `header` values in `message`.
  """
  @spec delete_header(message, header) :: message
  def delete_header(message, header) do
    %{message | headers: Map.delete(message.headers, header)}
  end

  @doc """
  Deletes the first value of `header` in `message`.
  """
  @spec delete_header_front(message, header) :: message
  def delete_header_front(message, header) do
    case get_header(message, header) do
      nil -> message
      [_] -> delete_header(message, header)
      [_|tail] -> %{message | headers: Map.put(message.headers, header, tail)}
    end
  end

  @doc """
  Deletes the last value of `header` in `message`.
  """
  @spec delete_header_back(message, header) :: message
  def delete_header_back(message, header) do
    case get_header(message, header) do
      nil -> message
      [_] -> delete_header(message, header)
      values -> %{message | headers:
          Map.put(message.headers, header, do_remove_last(values))}
    end
  end

  defp do_remove_last(list) do
    [_ | tail] = Enum.reverse(list)
    Enum.reverse(tail)
  end

  @doc """
  Drops all given `headers` from `message`.
  """
  @spec drop_headers(message, [header]) :: message
  def drop_headers(message, headers) do
    %{message | headers: Map.drop(message.headers, headers)}
  end

  @doc """
  Fetches all values for a specific `header` and returns it in a tuple.

  If the `header` does not exist, returns `:error`.
  """
  @spec fetch_header(message, header) :: {:ok, [value]} | :error
  def fetch_header(message, header) do
    Map.fetch(message.headers, header)
  end

  @doc """
  Fetches the first value of a specific `header` and returns it in a tuple.

  If the `header` does not exist, returns `:error`. If the `header` exists but
  it is an empty list, returns `{:ok, nil}`.
  """
  @spec fetch_header_front(message, header) :: {:ok, value} | :error
  def fetch_header_front(message, header) do
    case fetch_header(message, header) do
      {:ok, values} ->
          if Enum.empty?(values) do
            {:ok, nil}
          else
            {:ok, List.first(values)}
          end
      _ -> :error
    end
  end

  @doc """
  Fetches the last value of a specific `header` and returns it in a tuple.

  If the `header` does not exist, returns `:error`. If the `header` exists but
  it is an empty list, returns `{:ok, nil}`.
  """
  @spec fetch_header_back(message, header) :: {:ok, value} | :error
  def fetch_header_back(message, header) do
    case fetch_header(message, header) do
      {:ok, values} ->
          if Enum.empty?(values) do
            {:ok, nil}
          else
            {:ok, List.last(values)}
          end
      _ -> :error
    end
  end

  @doc """
  Fetches all values for a specific `header` in the given `message`, erroring
  out if `message` doesn't contain `header`.

  If `message` contains the given `header`, all corresponding values are
  returned in a list. If `message` doesn't contain the `header`, a `KeyError`
  exception is raised.
  """
  @spec fetch_header!(message, header) :: [value] | no_return
  def fetch_header!(message, header) do
    Map.fetch!(message.headers, header)
  end

  @doc """
  Fetches the first value of a specific `header` in the given `message`, erroring
  out if `message` doesn't contain `header`.

  If `message` contains the given `header`, the first value is returned, which
  may be `nil` case the values list is empty. If `message` doesn't contain the
  `header`, a `KeyError` exception is raised.
  """
  @spec fetch_header_front!(message, header) :: value | no_return
  def fetch_header_front!(message, header) do
    values = fetch_header!(message, header)
    if Enum.empty?(values) do
      nil
    else
      List.first(values)
    end
  end

  @doc """
  Fetches the last value of a specific `header` in the given `message`, erroring
  out if `message` doesn't contain `header`.

  If `message` contains the given `header`, the last value is returned, which
  may be `nil` case the values list is empty. If `message` doesn't contain the
  `header`, a `KeyError` exception is raised.
  """
  @spec fetch_header_back!(message, header) :: value | no_return
  def fetch_header_back!(message, header) do
    values = fetch_header!(message, header)
    if Enum.empty?(values) do
      nil
    else
      List.last(values)
    end
  end

  @doc """
  Gets all values for a specific `header` in `message`.

  If `header` is present in `message`, then all values are returned in a list.
  Otherwise, `default` is returned (which is `nil` unless specified otherwise).
  """
  @spec get_header(message, header) :: [value] | nil
  @spec get_header(message, header, any) :: [value] | any
  def get_header(message, header, default \\ nil) do
    Map.get(message.headers, header, default)
  end

  @doc """
  Gets the first value of a specific `header` in `message`.

  If `header` is present in `message`, then the first value is returned.
  Otherwise, `default` is returned (which is `nil` unless specified otherwise).
  """
  @spec get_header_front(message, header) :: value | nil
  @spec get_header_front(message, header, any) :: value | any
  def get_header_front(message, header, default \\ nil) do
    case get_header(message, header, nil) do
      nil -> default
      values -> List.first(values)
    end
  end

  @doc """
  Gets the last value of a specific `header` in `message`.

  If `header` is present in `message`, then the last value is returned.
  Otherwise, `default` is returned (which is `nil` unless specified otherwise).
  """
  @spec get_header_back(message, header) :: value | nil
  @spec get_header_back(message, header, any) :: value | any
  def get_header_back(message, header, default \\ nil) do
    case get_header(message, header, nil) do
      nil -> default
      values -> List.last(values)
    end
  end

  @doc """
  Updates the `header` in `message` with the given function.

  If `header` is present in `message` with value `[value]`, `fun` is invoked
  with argument `[value]` and its result is used as the new value of `header`.
  If `header` is not present in `message`, `[initial]` is inserted as the value
  of `header`.
  """
  @spec update_header(message, header, [value],
            ([value] -> [value])) :: message
  def update_header(message, header, initial, fun) do
    %{message | headers: Map.update(message.headers, header, initial, fun)}
  end

  @doc """
  Updates the first `header` value in `message` with the given function.

  If `header` is present in `message` with value `[value]`, `fun` is invoked
  with for first element of `[value]` and its result is used as the new value
  of `header` front.  If `header` is not present in `message`, or it is an empty
  list, `initial` is inserted as the single value of `header`.
  """
  @spec update_header_front(message, header, value,
            (value -> value)) :: message
  def update_header_front(message, header, initial, fun)
      when is_function(fun, 1) do
    update_header(message, header, [initial],
        fn [] -> [initial]
           [head|tail] -> [fun.(head)|tail]
        end)
  end

  @doc """
  Updates the last `header` value in `message` with the given function.

  If `header` is present in `message` with value `[value]`, `fun` is invoked
  with for last element of `[value]` and its result is used as the new value of
  `header` back.  If `header` is not present in `message`, or it is an empty
  list, `initial` is inserted as the single value of `header`.
  """
  @spec update_header_back(message, header, value, (value -> value)) :: message
  def update_header_back(message, header, initial, fun)
      when is_function(fun, 1) do
    update_header(message, header, [initial],
        fn [] -> [initial]
           values -> do_update_last(values, fun)
        end)
  end

  defp do_update_last(values, fun) do
    [last|tail] = Enum.reverse(values)
    Enum.reduce(tail, [fun.(last)], fn(x, acc) -> [x|acc] end)
  end

  @doc """
  Returns and removes the values associated with `header` in `message`.

  If `header` is present in `message` with values `[value]`, `{[value],
  new_message}` is returned where `new_message` is the result of removing
  `header` from `message`. If `header` is not present in `message`, `{default,
  message}` is returned.
  """
  @spec pop_header(message, header) :: {[value] | nil, message}
  @spec pop_header(message, header, any) :: {any, message}
  def pop_header(message, header, default \\ nil) do
    {get, new_headers} = Map.pop(message.headers, header, default)
    {get, %{message | headers: new_headers}}
  end

  @doc """
  Returns and removes the first value associated with `header` in `message`.

  If `header` is present in `message` with values `values`,
  `{List.first(values), new_message}` is returned where `new_message` is the
  result of removing `List.first(values)` from `header`.  If `header` is not
  present in `message` or it is an empty list, `{default, message}` is
  returned. When the `header` results in an empty list, `message` gets updated
  by removing the header.
  """
  @spec pop_header_front(message, header) :: {value | nil, message}
  @spec pop_header_front(message, header, any) :: {value | any, message}
  def pop_header_front(message, header, default \\ nil) do
    {values, new_headers} = Map.pop(message.headers, header, [])
    case values do
      [] ->
          {default, %{message | headers: new_headers}}
      [value] ->
          {value, %{message | headers: new_headers}}
      [head|tail] ->
          {head, %{message | headers: Map.put(message.headers, header, tail)}}
    end
  end

  @doc """
  Returns and removes the last value associated with `header` in `message`.

  If `header` is present in `message` with values `values`,
  `{List.last(values), new_message}` is returned where `new_message` is the
  result of removing `List.last(values)` from `header`.  If `header` is not
  present in `message` or it is an empty list, `{default, message}` is
  returned. When the `header` results in an empty list, `message` gets updated
  by removing the header.
  """
  @spec pop_header_back(message, header) :: {value | nil, message}
  @spec pop_header_back(message, header, any) :: {value | any, message}
  def pop_header_back(message, header, default \\ nil) do
    {values, new_headers} = Map.pop(message.headers, header, [])
    case Enum.reverse(values) do
      [] ->
          {default, %{message | headers: new_headers}}
      [value] ->
          {value, %{message | headers: new_headers}}
      [last|tail] ->
          {last, %{message | headers:
              Map.put(message.headers, header, Enum.reverse(tail))}}
    end
  end

  @doc """
  Gets the values from `header` and updates it, all in one pass.

  `fun` is called with the current values under `header` in `message` (or `nil`
  if `key` is not present in `message`) and must return a two-element tuple:
  the "get" value (the retrieved values, which can be operated on before being
  returned) and the new values to be stored under `header` in the resulting new
  message. `fun` may also return `:pop`, which means all current values shall
  be removed from `message` and returned (making this function behave like
  `Sippet.Message.pop_header(message, header)`. The returned value is a tuple
  with the "get" value returned by `fun` and a new message with the updated
  values under `header`.
  """
  @spec get_and_update_header(message, header,
            ([value] -> {get, [value]} | :pop)) ::
                {get, message} when get: [value]
  def get_and_update_header(message, header, fun) when is_function(fun, 1) do
    {get, new_headers} = Map.get_and_update(message.headers, header, fun)
    {get, %{message | headers: new_headers}}
  end

  @doc """
  Gets the first value from `header` and updates it, all in one pass.

  `fun` is called with the current first value under `header` in `message` (or
  `nil` if `key` is not present in `message`) and must return a two-element
  tuple: the "get" value (the retrieved value, which can be operated on before
  being returned) and the new value to be stored under `header` in the
  resulting new message. `fun` may also return `:pop`, which means the current
  value shall be removed from `message` and returned (making this function
  behave like `Sippet.Message.pop_header_front(message, header)`. The returned
  value is a tuple with the "get" value returned by `fun` and a new message
  with the updated values under `header`.
  """
  @spec get_and_update_header_front(message, header,
            (value -> {get, value} | :pop)) ::
                {get, message} when get: value
  def get_and_update_header_front(message, header, fun)
      when is_function(fun, 1) do
    {get, new_headers} = Map.get_and_update(message.headers, header,
        &do_get_and_update_header_front(&1, fun))
    {get, %{message | headers: new_headers}}
  end

  defp do_get_and_update_header_front(nil, fun) do
    case fun.(nil) do
      {get, nil} -> {get, []}
      {get, value} -> {get, [value]}
      :pop -> :pop
    end
  end

  defp do_get_and_update_header_front([], fun) do
    case fun.(nil) do
      {get, nil} -> {get, []}
      {get, value} -> {get, [value]}
      :pop -> :pop
    end
  end

  defp do_get_and_update_header_front([head|tail], fun) do
    case fun.(head) do
      {get, nil} -> {get, [tail]}
      {get, value} -> {get, [value|tail]}
      :pop -> {head, tail}
    end
  end

  @doc """
  Gets the last value from `header` and updates it, all in one pass.

  `fun` is called with the current last value under `header` in `message` (or
  `nil` if `key` is not present in `message`) and must return a two-element
  tuple: the "get" value (the retrieved value, which can be operated on before
  being returned) and the new value to be stored under `header` in the
  resulting new message. `fun` may also return `:pop`, which means the current
  value shall be removed from `message` and returned (making this function
  behave like `Sippet.Message.pop_header_back(message, header)`. The returned
  value is a tuple with the "get" value returned by `fun` and a new message
  with the updated values under `header`.
  """
  @spec get_and_update_header_back(message, header,
            (value -> {get, value} | :pop)) ::
                {get, message} when get: value
  def get_and_update_header_back(message, header, fun)
      when is_function(fun, 1) do
    {get, new_headers} = Map.get_and_update(message.headers, header,
        &do_get_and_update_header_back(&1, fun))
    {get, %{message | headers: new_headers}}
  end

  defp do_get_and_update_header_back([], fun) do
    case fun.(nil) do
      {get, value} -> {get, [value]}
      :pop -> :pop
    end
  end

  defp do_get_and_update_header_back(values, fun) do
    [last|tail] = Enum.reverse(values)
    case fun.(last) do
      {get, new_value} -> {get, Enum.reduce(tail, [new_value],
          fn(x, acc) -> [x|acc] end)}
      :pop -> {last, Enum.reverse(last)}
    end
  end

  @doc """
  Parses a SIP message header block as received by the transport layer.

  In order to correctly set the message body, you have to verify the
  `:content_length` header; if it exists, it reflects the body size and you
  have to set it manually on the returned message.
  """
  @spec parse(iodata) :: {:ok, t} | {:error, atom}
  def parse(data) do
    case Sippet.Parser.parse(IO.iodata_to_binary(data)) do
      {:ok, message} -> {:ok, do_parse(message)}
      other -> other
    end
  end

  defp do_parse(message) do
    %__MODULE__{
      start_line: do_parse_start_line(message.start_line),
      headers: do_parse_headers(message.headers)
    }
  end

  defp do_parse_start_line(%{method: _} = start_line) do
    %RequestLine{
      method: start_line.method,
      request_uri: URI.parse(start_line.request_uri),
      version: start_line.version
    }
  end

  defp do_parse_start_line(%{status_code: _} = start_line) do
    %StatusLine{
      status_code: start_line.status_code,
      reason_phrase: start_line.reason_phrase,
      version: start_line.version
    }
  end

  defp do_parse_headers(%{} = headers) do
    do_parse_headers(Map.to_list(headers), [])
  end
  defp do_parse_headers([], result) do
    Map.new(result)
  end
  defp do_parse_headers([{name, value}|tail], result) do
    do_parse_headers(tail, [{name, do_parse_header_value(value)}|result])
  end

  defp do_parse_header_value(values) when is_list(values) do
    do_parse_header_value(values, [])
  end

  defp do_parse_header_value({{year, month, day}, {hour, minute, second},
      microsecond}) do
    NaiveDateTime.from_erl!({{year, month, day}, {hour, minute, second}},
        microsecond)
  end
  defp do_parse_header_value({display_name, uri, %{} = parameters}) do
    {display_name, URI.parse(uri), parameters}
  end
  defp do_parse_header_value(value) do
    value
  end

  defp do_parse_header_value([], result) do
    Enum.reverse(result)
  end
  defp do_parse_header_value([head|tail], result) do
    do_parse_header_value(tail, [do_parse_header_value(head)|result])
  end

  @doc """
  Parses a SIP message header block as received by the transport layer.

  Raises if the string is an invalid SIP header.

  In order to correctly set the message body, you have to verify the
  `:content_length` header; if it exists, it reflects the body size and you
  have to set it manually on the returned message.
  """
  @spec parse!(String.t | charlist) :: t | no_return
  def parse!(data) do
    case parse(data) do
      {:ok, message} ->
        message
      {:error, reason} ->
        raise ArgumentError, "cannot convert #{inspect data} to SIP message, reason: #{inspect reason}"
    end
  end

  @doc """
  Returns the string representation of the given `Sippet.Message` struct.
  """
  @spec to_string(t) :: binary
  defdelegate to_string(value), to: String.Chars.Sippet.Message
end

defimpl String.Chars, for: Sippet.Message do
  def to_string(%Sippet.Message{} = message) do
    Kernel.to_string(message.start_line) <> "\n" <>
      do_headers(message.headers) <> "\n" <>
      if(message.body == nil, do: "", else: message.body)
  end

  defp do_headers(%{} = headers) do
    do_headers(Map.to_list(headers), "")
  end

  defp do_headers([], header) do
    header
  end
  defp do_headers([{name, value}|tail], header) do
    do_headers(tail, header <> do_header(name, value))
  end

  defp do_header(name, value) do
    {name, multiple} = case name do
      :accept -> {"Accept", true}
      :accept_encoding -> {"Accept-Encoding", true}
      :accept_language -> {"Accept-Language", true}
      :alert_info -> {"Alert-Info", true}
      :allow -> {"Allow", true}
      :authentication_info -> {"Authentication-Info", false}
      :authorization -> {"Authorization", false}
      :call_id -> {"Call-ID", true}
      :call_info -> {"Call-Info", true}
      :contact -> {"Contact", true}
      :content_disposition -> {"Content-Disposition", true}
      :content_encoding -> {"Content-Encoding", true}
      :content_language -> {"Content-Language", true}
      :content_length -> {"Content-Length", true}
      :content_type -> {"Content-Type", true}
      :cseq -> {"CSeq", true}
      :date -> {"Date", true}
      :error_info -> {"Error-Info", true}
      :expires -> {"Expires", true}
      :from -> {"From", true}
      :in_reply_to -> {"In-Reply-To", true}
      :max_forwards -> {"Max-Forwards", true}
      :mime_version -> {"MIME-Version", true}
      :min_expires -> {"Min-Expires", true}
      :organization -> {"Organization", true}
      :priority -> {"Priority", true}
      :proxy_authenticate -> {"Proxy-Authenticate", false}
      :proxy_authorization -> {"Proxy-Authorization", false}
      :proxy_require -> {"Proxy-Require", true}
      :reason -> {"Reason", true}
      :record_route -> {"Record-Route", true}
      :reply_to -> {"Reply-To", true}
      :require -> {"Require", true}
      :retry_after -> {"Retry-After", true}
      :route -> {"Route", true}
      :server -> {"Server", true}
      :subject -> {"Subject", true}
      :supported -> {"Supported", true}
      :timestamp -> {"Timestamp", true}
      :to -> {"To", true}
      :unsupported -> {"Unsupported", true}
      :user_agent -> {"User-Agent", true}
      :via -> {"Via", true}
      :warning -> {"Warning", true}
      :www_authenticate -> {"WWW-Authenticate", false}
    end
    if multiple do
      name <> ": " <> do_header_values(value, []) <> "\n"
    else
      do_one_per_line(name, value)
    end
  end

  defp do_header_values([], values) do
    Enum.join(values, ", ")
  end
  defp do_header_values([head|tail], values) do
    do_header_values(tail, [do_header_value(head)|values])
  end
  defp do_header_values(value, _) do
    do_header_value(value)
  end

  defp do_header_value(value) when is_binary(value) do
    value
  end

  defp do_header_value(value) when is_integer(value) do
    Integer.to_string(value)
  end

  defp do_header_value({sequence, method})
      when is_integer(sequence) do
    Integer.to_string(sequence) <> " " <> upcase_atom_or_string(method)
  end

  defp do_header_value({major, minor})
      when is_integer(major) and is_integer(minor) do
    Integer.to_string(major) <> "." <> Integer.to_string(minor)
  end

  defp do_header_value({token, %{} = parameters})
      when is_binary(token) do
    token <> do_parameters(parameters)
  end

  defp do_header_value({{type, subtype}, %{} = parameters})
      when is_binary(type) and is_binary(subtype) do
    type <> "/" <> subtype <> do_parameters(parameters)
  end

  defp do_header_value({display_name, uri, %{} = parameters})
      when is_binary(display_name) and is_binary(uri) do
    if(display_name == "", do: "", else: "\"" <> display_name <> "\" ")
      <> "<" <> uri <> ">"
      <> do_parameters(parameters)
  end

  defp do_header_value({delta_seconds, comment, %{} = parameters})
      when is_integer(delta_seconds) and is_binary(comment) do
    Integer.to_string(delta_seconds) <>
      if(comment != "", do: " (" <> comment <> ") ", else: "") <>
      do_parameters(parameters)
  end

  defp do_header_value({timestamp, delay})
      when is_float(timestamp) and is_float(delay) do
    Float.to_string(timestamp) <>
      if(delay > 0, do: " " <> Float.to_string(delay), else: "")
  end

  defp do_header_value({{major, minor}, protocol, {host, port},
      %{} = parameters}) when is_integer(major) and is_integer(minor)
          and is_binary(host) and is_integer(port) do
    "SIP/" <> Integer.to_string(major) <> "." <> Integer.to_string(minor) <>
      "/" <> upcase_atom_or_string(protocol) <>
      " " <> host <>
      if(port != -1, do: ":" <> Integer.to_string(port), else: "") <>
      do_parameters(parameters)
  end

  defp do_header_value({code, agent, text})
      when is_integer(code) and is_binary(agent) and is_binary(text) do
    Integer.to_string(code) <> " " <> agent <> " \"" <> text <> "\""
  end

  defp do_header_value(%NaiveDateTime{} = value) do
    day_of_week = case Date.day_of_week(NaiveDateTime.to_date(value)) do
      1 -> "Mon"
      2 -> "Tue"
      3 -> "Wed"
      4 -> "Thu"
      5 -> "Fri"
      6 -> "Sat"
      7 -> "Sun"
    end

    month = case value.month do
      1 -> "Jan"
      2 -> "Feb"
      3 -> "Mar"
      4 -> "Apr"
      5 -> "May"
      6 -> "Jun"
      7 -> "Jul"
      8 -> "Aug"
      9 -> "Sep"
      10 -> "Oct"
      11 -> "Nov"
      12 -> "Dec"
    end

    # Microsecond is explicitly removed here, as the RFC 3261 does not define
    # it. Therefore, while it is accepted, it won't be forwarded.
    day_of_week <> ", " <>
      String.pad_leading(Integer.to_string(value.day), 2, "0") <> " " <>
      month <> " " <>
      Integer.to_string(value.year) <> " " <>
      String.pad_leading(Integer.to_string(value.hour), 2, "0") <> ":" <>
      String.pad_leading(Integer.to_string(value.minute), 2, "0") <> ":" <>
      String.pad_leading(Integer.to_string(value.second), 2, "0") <> " GMT"
  end

  defp do_one_per_line(name, values) when is_list(values) do
    do_one_per_line(name, values, "")
  end
  defp do_one_per_line(name, %{} = value) do
    name <> ": " <> do_one_per_line_value(value) <> "\n"
  end

  defp do_one_per_line(_, [], result) do
    result
  end
  defp do_one_per_line(name, [head|tail], result) do
    do_one_per_line(name, tail,
      result <> name <> ": " <> do_one_per_line_value(head) <> "\n")
  end

  defp do_one_per_line_value(%{} = parameters) do
    do_one_per_line_value(Map.to_list(parameters), [])
  end

  defp do_one_per_line_value({scheme, %{} = parameters}) do
    scheme <> " " <>
      do_one_per_line_value(Map.to_list(parameters), [])
  end

  defp do_one_per_line_value([], result) do
    Enum.join(result, ", ")
  end
  defp do_one_per_line_value([{name, value}|tail], result) do
    do_one_per_line_value(tail, [name <> "=" <> value | result])
  end

  defp do_parameters(%{} = parameters) do
    do_parameters(Map.to_list(parameters), [])
  end
  defp do_parameters([], pairs) do
    if length(pairs) == 0 do
      ""
    else
      ";" <> Enum.join(pairs, ";")
    end
  end
  defp do_parameters([{name, value}|tail], pairs) do
    do_parameters(tail, [name <> "=" <> value | pairs])
  end

  defp upcase_atom_or_string(s) do
    if(is_atom(s), do: String.upcase(Atom.to_string(s)), else: s)
  end
end
