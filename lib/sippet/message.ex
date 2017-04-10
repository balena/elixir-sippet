defmodule Sippet.Message do
  @moduledoc """
  Message primitive for composing SIP messages.
  Build a SIP message with the `Sippet.Message` struct.

      request =
        Sippet.Message.build_request("INVITE", "sip:joe@example.com")
        |> Sippet.Message.put_header(:to,
            {"", Sippet.URI.parse("sip:joe@example.com"), %{}})
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

  @type method ::
    :ack |
    :bye |
    :cancel |
    :info |
    :invite |
    :message |
    :notify |
    :options |
    :prack |
    :publish |
    :pull |
    :push |
    :refer |
    :register |
    :store |
    :subscribe |
    :update |
    binary

  @type header ::
    :accept |
    :accept_encoding |
    :accept_language |
    :alert_info |
    :allow |
    :authentication_info |
    :authorization |
    :call_id |
    :call_info |
    :contact |
    :content_disposition |
    :content_encoding |
    :content_language |
    :content_length |
    :content_type |
    :cseq |
    :date |
    :error_info |
    :expires |
    :from |
    :in_reply_to |
    :max_forwards |
    :mime_version |
    :min_expires |
    :organization |
    :priority |
    :proxy_authenticate |
    :proxy_authorization |
    :proxy_require |
    :reason |
    :record_route |
    :reply_to |
    :require |
    :retry_after |
    :route |
    :server |
    :subject |
    :supported |
    :timestamp |
    :to |
    :unsupported |
    :user_agent |
    :via |
    :warning |
    :www_authenticate |
    binary

  @type protocol ::
    :dccp |
    :dtls |
    :sctp |
    :stomp |
    :tcp |
    :tls |
    :udp |
    :ws |
    :wss |
    binary

  @type token_params ::
    {token :: binary, params :: %{}}

  @type type_subtype_params ::
    {{type :: binary, subtype :: binary}, params :: %{}}

  @type uri_params ::
    {display_name :: binary, uri :: URI.t, params :: %{}}

  @type via_value ::
    {{major :: integer, minor :: integer}, protocol,
        {host :: binary, port :: integer}, params :: %{}}

  @type single_value ::
    binary |
    integer |
    {sequence :: integer, method} |
    {major :: integer, minor :: integer} |
    token_params |
    type_subtype_params |
    uri_params |
    {delta_seconds :: integer, comment :: binary, params :: %{}} |
    {timestamp :: integer, delay :: integer} |
    NativeDateTime.t

  @type multiple_value ::
    token_params |
    type_subtype_params |
    uri_params |
    via_value |
    auth_params :: %{} |
    {scheme :: binary, params :: %{}} |
    {code :: integer, agent :: binary, text :: binary}

  @type value ::
    single_value |
    [multiple_value]

  @type t :: %__MODULE__{
    start_line: RequestLine.t | StatusLine.t,
    headers: %{header => value},
    body: String.t | nil
  }

  @type request :: %__MODULE__{
    start_line: RequestLine.t,
    headers: %{header => value},
    body: String.t | nil
  }

  @type response :: %__MODULE__{
    start_line: StatusLine.t,
    headers: %{header => value},
    body: String.t | nil
  }

  defmacrop is_method(data) do
    quote do
      is_atom(unquote(data)) or is_binary(unquote(data))
    end
  end

  @doc """
  Build a SIP request.
  """
  @spec build_request(method, uri | binary) :: request
  def build_request(method, request_uri) when is_method(method),
    do: %__MODULE__{start_line: RequestLine.build(method, request_uri)}

  @doc """
  Build a SIP response.
  """
  @spec build_response(integer | StatusLine.t) :: response
  @spec build_response(integer | request,
                       integer | String.t | StatusLine.t) :: response
  @spec build_response(request, integer, String.t) :: response

  def build_response(%StatusLine{} = status_line),
    do: %__MODULE__{start_line: status_line}

  def build_response(status_code) when is_integer(status_code),
    do: build_response(StatusLine.build(status_code))

  def build_response(status_code, reason_phrase)
    when is_integer(status_code) and is_binary(reason_phrase),
    do: build_response(StatusLine.build(status_code, reason_phrase))

  def build_response(%__MODULE__{start_line: %RequestLine{}} = request,
      %StatusLine{} = status_line) do
    response =
      build_response(status_line)
      |> put_header(:via, get_header(request, :via))
      |> put_header(:from, get_header(request, :from))
      |> put_header(:to, get_header(request, :to))
      |> put_header(:call_id, get_header(request, :call_id))
      |> put_header(:cseq, get_header(request, :cseq))

    response =
      if status_line.status_code > 100 and
          not Map.has_key?(elem(response.headers.to, 2), "tag") do
        {display_name, uri, params} = response.headers.to
        params = Map.put(params, "tag", create_tag())
        response |> put_header(:to, {display_name, uri, params})
      else
        response
      end

    if has_header?(request, :record_route) do
      response |> put_header(:record_route, get_header(request, :record_route))
    else
      response
    end
  end

  def build_response(request, status_code) when is_integer(status_code),
    do: build_response(request, StatusLine.build(status_code))

  def build_response(request, status_code, reason_phrase)
    when is_integer(status_code) and is_binary(reason_phrase),
    do: build_response(request, StatusLine.build(status_code, reason_phrase))

  @doc """
  Creates a local tag (48-bit random string, 8 characters long).
  """
  @spec create_tag() :: binary
  def create_tag(), do: do_random_string(48)

  defp do_random_string(length) do
    bytes = round(Float.ceil(length / 8))
    :crypto.strong_rand_bytes(bytes) |> Base.url_encode64(padding: false)
  end

  @doc """
  Creates an unique local branch (72-bit random string, 7+12 characters long).
  """
  @spec create_branch() :: binary
  def create_branch(), do: "z9hG4bK" <> do_random_string(72)

  @doc """
  Creates an unique Call-ID (120-bit random string, 20 characters long).
  """
  @spec create_call_id() :: binary
  def create_call_id(), do: do_random_string(120)

  @doc """
  Shortcut to check if the message is a request.
  """
  @spec request?(t) :: boolean
  def request?(%__MODULE__{start_line: %RequestLine{}} = _), do: true
  def request?(_), do: false

  @doc """
  Shortcut to check if the message is a response.
  """
  @spec response?(t) :: boolean
  def response?(%__MODULE__{start_line: %StatusLine{}} = _), do: true
  def response?(_), do: false

  @doc """
  Returns whether a given `header` exists in the given `message`.
  """
  @spec has_header?(t, header) :: boolean
  def has_header?(message, header) do
    Map.has_key?(message.headers, header)
  end

  @doc """
  Puts the `value` under `header` on the `message`.
  """
  @spec put_header(t, header, value) :: t
  def put_header(message, header, value) do
    %{message | headers: Map.put(message.headers, header, value)}
  end

  @doc """
  Puts the `value` under `header` on the `message` unless the `header` already
  exists.
  """
  @spec put_new_header(t, header, value) :: t
  def put_new_header(message, header, value) do
    case has_header?(message, header) do
      true -> message
      false -> put_header(message, header, value)
    end
  end

  @doc """
  Evaluates `fun` and puts the result under `header` in `message` unless
  `header` is already present.

  This function is useful in case you want to compute the value to put under
  `header` only if `header` is not already present (e.g., the value is
  expensive to calculate or generally difficult to setup and teardown again).
  """
  @spec put_new_lazy_header(t, header, (() -> value)) :: t
  def put_new_lazy_header(message, header, fun) when is_function(fun, 0) do
    case has_header?(message, header) do
      true -> message
      false -> put_header(message, header, fun.())
    end
  end

  @doc """
  Puts the `value` under `header` on the `message`, as front element.

  If the parameter `value` is `nil`, then the empty list will be prefixed to
  the `header`.
  """
  @spec put_header_front(t, header, value) :: t
  def put_header_front(message, header, value) do
    existing = get_header(message, header, [])

    new_list =
      case value do
        nil -> existing
        _ -> [value|existing]
      end

    put_header(message, header, new_list)
  end

  @doc """
  Puts the `value` under `header` on the `message`, as last element.

  If the parameter `value` is `nil`, then the empty list will be appended to
  the `header`.
  """
  @spec put_header_back(t, header, value) :: t
  def put_header_back(message, header, value) do
    existing = get_header(message, header, [])

    new_list =
      case value do
        nil -> existing
        _ -> List.foldr(existing, [value], fn(x, acc) -> [x|acc] end)
      end

    put_header(message, header, new_list)
  end

  @doc """
  Deletes all `header` values in `message`.
  """
  @spec delete_header(t, header) :: t
  def delete_header(message, header) do
    %{message | headers: Map.delete(message.headers, header)}
  end

  @doc """
  Deletes the first value of `header` in `message`.
  """
  @spec delete_header_front(t, header) :: t
  def delete_header_front(message, header) do
    case get_header(message, header) do
      nil -> message
      [_] -> delete_header(message, header)
      [_|tail] -> put_header(message, header, tail)
    end
  end

  @doc """
  Deletes the last value of `header` in `message`.
  """
  @spec delete_header_back(t, header) :: t
  def delete_header_back(message, header) do
    case get_header(message, header) do
      nil -> message
      [_] -> delete_header(message, header)
      [_|_] = values -> put_header(message, header, do_remove_last(values))
    end
  end

  defp do_remove_last(list) when is_list(list) do
    [_ | tail] = Enum.reverse(list)
    Enum.reverse(tail)
  end

  @doc """
  Drops all given `headers` from `message`.
  """
  @spec drop_headers(t, [header]) :: t
  def drop_headers(message, headers) do
    %{message | headers: Map.drop(message.headers, headers)}
  end

  @doc """
  Fetches all values for a specific `header` and returns it in a tuple.

  If the `header` does not exist, returns `:error`.
  """
  @spec fetch_header(t, header) :: {:ok, value} | :error
  def fetch_header(message, header) do
    Map.fetch(message.headers, header)
  end

  @doc """
  Fetches the first value of a specific `header` and returns it in a tuple.

  If the `header` does not exist, returns `:error`. If the `header` exists but
  it is an empty list, returns `{:ok, nil}`.
  """
  @spec fetch_header_front(t, header) :: {:ok, value} | :error
  def fetch_header_front(message, header) do
    case fetch_header(message, header) do
      {:ok, values} ->
        if Enum.empty?(values) do
          {:ok, nil}
        else
          {:ok, List.first(values)}
        end
      _otherwise ->
        :error
    end
  end

  @doc """
  Fetches the last value of a specific `header` and returns it in a tuple.

  If the `header` does not exist, returns `:error`. If the `header` exists but
  it is an empty list, returns `{:ok, nil}`.
  """
  @spec fetch_header_back(t, header) :: {:ok, value} | :error
  def fetch_header_back(message, header) do
    case fetch_header(message, header) do
      {:ok, values} ->
        if Enum.empty?(values) do
          {:ok, nil}
        else
          {:ok, List.last(values)}
        end
      _otherwise ->
        :error
    end
  end

  @doc """
  Fetches all values for a specific `header` in the given `message`, erroring
  out if `message` doesn't contain `header`.

  If `message` contains the given `header`, all corresponding values are
  returned in a list. If `message` doesn't contain the `header`, a `KeyError`
  exception is raised.
  """
  @spec fetch_header!(t, header) :: value | no_return
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
  @spec fetch_header_front!(t, header) :: value | no_return
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
  @spec fetch_header_back!(t, header) :: value | no_return
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
  @spec get_header(t, header) :: value | nil
  @spec get_header(t, header, any) :: value | any
  def get_header(message, header, default \\ nil) do
    Map.get(message.headers, header, default)
  end

  @doc """
  Gets the first value of a specific `header` in `message`.

  If `header` is present in `message`, then the first value is returned.
  Otherwise, `default` is returned (which is `nil` unless specified otherwise).
  """
  @spec get_header_front(t, header) :: value | nil
  @spec get_header_front(t, header, any) :: value | any
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
  @spec get_header_back(t, header) :: value | nil
  @spec get_header_back(t, header, any) :: value | any
  def get_header_back(message, header, default \\ nil) do
    case get_header(message, header, nil) do
      nil -> default
      values -> List.last(values)
    end
  end

  @doc """
  Updates the `header` in `message` with the given function.

  If `header` is present in `message` with value `value`, `fun` is invoked
  with argument `value` and its result is used as the new value of `header`.
  If `header` is not present in `message`, `initial` is inserted as the value
  of `header`.
  """
  @spec update_header(t, header, value,
            (value -> value)) :: t
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
  @spec update_header_front(t, header, value, (value -> value)) :: t
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
  @spec update_header_back(t, header, value, (value -> value)) :: t
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
  @spec pop_header(t, header) :: {value | nil, t}
  @spec pop_header(t, header, any) :: {value | any, t}
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
  @spec pop_header_front(t, header) :: {value | nil, t}
  @spec pop_header_front(t, header, any) :: {value | any, t}
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
  @spec pop_header_back(t, header) :: {value | nil, t}
  @spec pop_header_back(t, header, any) :: {value | any, t}
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
  @spec get_and_update_header(t, header,
            (value -> {get, value} | :pop)) ::
                {get, t} when get: value
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
  @spec get_and_update_header_front(t, header,
            (value -> {get, value} | :pop)) ::
                {get, t} when get: value
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
  @spec get_and_update_header_back(t, header,
            (value -> {get, value} | :pop)) ::
                {get, t} when get: value
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
      {:ok, message} ->
        case do_parse(message) do
          {:error, reason} ->
            {:error, reason}
          message ->
            {:ok, message}
        end
      other ->
        other
    end
  end

  defp do_parse(message) do
    case do_parse_start_line(message.start_line) do
      {:error, reason} ->
        {:error, reason}
      start_line ->
        case do_parse_headers(message.headers) do
          {:error, reason} ->
            {:error, reason}
          headers ->
            %__MODULE__{
              start_line: start_line,
              headers: headers
            }
        end
    end
  end

  defp do_parse_start_line(%{method: _} = start_line) do
    case URI.parse(start_line.request_uri) do
      {:ok, uri} ->
        %RequestLine{
          method: start_line.method,
          request_uri: uri,
          version: start_line.version
        }
      other ->
        other
    end
  end

  defp do_parse_start_line(%{status_code: _} = start_line) do
    %StatusLine{
      status_code: start_line.status_code,
      reason_phrase: start_line.reason_phrase,
      version: start_line.version
    }
  end

  defp do_parse_headers(%{} = headers),
    do: do_parse_headers(Map.to_list(headers), [])

  defp do_parse_headers([], result), do: Map.new(result)
  defp do_parse_headers([{name, value} | tail], result) do
    case do_parse_header_value(value) do
      {:error, reason} ->
        {:error, reason}
      value ->
        do_parse_headers(tail, [{name, value} | result])
    end
  end

  defp do_parse_header_value(values) when is_list(values),
    do: do_parse_each_header_value(values, [])

  defp do_parse_header_value({{year, month, day}, {hour, minute, second},
      microsecond}) do
    NaiveDateTime.from_erl!({{year, month, day}, {hour, minute, second}},
        microsecond)
  end

  defp do_parse_header_value({display_name, uri, %{} = parameters}) do
    case URI.parse(uri) do
      {:ok, uri} ->
        {display_name, uri, parameters}
      other ->
        other
    end
  end

  defp do_parse_header_value(value), do: value

  defp do_parse_each_header_value([], result), do: Enum.reverse(result)
  defp do_parse_each_header_value([head | tail], result) do
    case do_parse_header_value(head) do
      {:error, reason} ->
        {:error, reason}
      value ->
        do_parse_each_header_value(tail, [value | result])
    end
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
        raise ArgumentError, "cannot convert #{inspect data} to SIP " <>
            "message, reason: #{inspect reason}"
    end
  end

  @doc """
  Returns the string representation of the given `Sippet.Message` struct.
  """
  @spec to_string(t) :: binary
  defdelegate to_string(value), to: String.Chars.Sippet.Message

  @doc """
  Returns the iodata representation of the given `Sippet.Message` struct.
  """
  @spec to_iodata(t) :: iodata
  def to_iodata(%Sippet.Message{} = message) do
    start_line =
      case message.start_line do
        %RequestLine{} -> RequestLine.to_iodata(message.start_line)
        %StatusLine{} -> StatusLine.to_iodata(message.start_line)
      end

    [start_line, "\n",
      do_headers(message.headers), "\n",
      if(message.body == nil, do: "", else: message.body)]
  end

  defp do_headers(%{} = headers), do: do_headers(Map.to_list(headers), [])
  defp do_headers([], result), do: result
  defp do_headers([{name, value}|tail], result),
    do: do_headers(tail, [do_header(name, value) | result])

  defp do_header(name, value) do
    {name, multiple} =
      case name do
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
      [name, ": ", do_header_values(value, []), "\n"]
    else
      do_one_per_line(name, value)
    end
  end

  defp do_header_values([], values), do: values
  defp do_header_values([head|tail], values),
    do: do_header_values(tail, do_join(do_header_value(head), values, ", "))

  defp do_header_values(value, _), do: do_header_value(value)

  defp do_header_value(value) when is_binary(value), do: value

  defp do_header_value(value) when is_integer(value), do: Integer.to_string(value)

  defp do_header_value({sequence, method}) when is_integer(sequence),
    do: [Integer.to_string(sequence), " ", upcase_atom_or_string(method)]

  defp do_header_value({major, minor})
      when is_integer(major) and is_integer(minor),
    do: [Integer.to_string(major), ".", Integer.to_string(minor)]

  defp do_header_value({token, %{} = parameters}) when is_binary(token),
    do: [token, do_parameters(parameters)]

  defp do_header_value({{type, subtype}, %{} = parameters})
      when is_binary(type) and is_binary(subtype),
    do: [type, "/", subtype, do_parameters(parameters)]

  defp do_header_value({display_name, %URI{} = uri, %{} = parameters})
      when is_binary(display_name) do
    [if(display_name == "", do: "", else: ["\"", display_name, "\" "]),
      "<", URI.to_string(uri), ">", do_parameters(parameters)]
  end

  defp do_header_value({delta_seconds, comment, %{} = parameters})
      when is_integer(delta_seconds) and is_binary(comment) do
    [Integer.to_string(delta_seconds),
      if(comment != "", do: [" (", comment, ") "], else: ""),
      do_parameters(parameters)]
  end

  defp do_header_value({timestamp, delay})
      when is_float(timestamp) and is_float(delay) do
    [Float.to_string(timestamp),
      if(delay > 0, do: [" ", Float.to_string(delay)], else: "")]
  end

  defp do_header_value({{major, minor}, protocol, {host, port},
      %{} = parameters}) when is_integer(major) and is_integer(minor)
          and is_binary(host) and is_integer(port) do
    ["SIP/", Integer.to_string(major), ".", Integer.to_string(minor),
      "/", upcase_atom_or_string(protocol),
      " ", host,
      if(port != -1, do: [":", Integer.to_string(port)], else: ""),
      do_parameters(parameters)]
  end

  defp do_header_value({code, agent, text})
      when is_integer(code) and is_binary(agent) and is_binary(text) do
    [Integer.to_string(code), " ", agent, " \"", text, "\""]
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
    [day_of_week, ", ",
      String.pad_leading(Integer.to_string(value.day), 2, "0"), " ",
      month, " ",
      Integer.to_string(value.year), " ",
      String.pad_leading(Integer.to_string(value.hour), 2, "0"), ":",
      String.pad_leading(Integer.to_string(value.minute), 2, "0"), ":",
      String.pad_leading(Integer.to_string(value.second), 2, "0"), " GMT"]
  end

  defp do_one_per_line(name, %{} = value),
    do: [name, ": ", do_one_per_line_value(value), "\n"]

  defp do_one_per_line(name, values) when is_list(values),
    do: do_one_per_line(name, values, [])

  defp do_one_per_line(_, [], result), do: result
  defp do_one_per_line(name, [head|tail], result) do
    do_one_per_line(name, tail,
      [name, ": ", do_one_per_line_value(head), "\n" | result])
  end

  defp do_one_per_line_value(%{} = parameters),
    do: do_one_per_line_value(Map.to_list(parameters), [])

  defp do_one_per_line_value({scheme, %{} = parameters}),
    do: [scheme, " ", do_one_per_line_value(Map.to_list(parameters), [])]

  defp do_one_per_line_value([], result), do: result
  defp do_one_per_line_value([{name, value}|tail], result) do
    do_one_per_line_value(tail, do_join([name, "=", value], result, ", "))
  end

  defp do_parameters(%{} = parameters),
    do: do_parameters(Map.to_list(parameters), [])
  defp do_parameters([], result), do: result
  defp do_parameters([{name, value}|tail], result),
    do: do_parameters(tail, [";", name, "=", value | result])

  defp do_join(head, [], _joiner), do: [head]
  defp do_join(head, tail, joiner), do: [head, joiner | tail]

  defp upcase_atom_or_string(s),
    do: if(is_atom(s), do: String.upcase(Atom.to_string(s)), else: s)
end

defimpl String.Chars, for: Sippet.Message do
  def to_string(%Sippet.Message{} = message),
    do: Sippet.Message.to_iodata(message) |> IO.iodata_to_binary
end
