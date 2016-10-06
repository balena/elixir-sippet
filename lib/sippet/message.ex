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
  Parses a SIP message header block as received by the transport layer. In
  order to correctly set the message body, you have to verify the
  `:content_length` header; if it exists, it must reflect the body size, if the
  transport is datagram based, the body is the remaining of the packet,
  otherwise it is a protocol error.
  """
  def parse(data) when is_binary(data) do
    [start_line | headers] = String.split(data, ~r{\r?\n}, trim: true)
    %__MODULE__{
      start_line: do_parse_start_line(start_line),
      headers: do_parse_headers(headers)
    }
  end

  defp do_parse_start_line(start_line) do
    case String.split(start_line, " ", parts: 3) do
      [method, request_uri, "SIP/2.0"] ->
          RequestLine.build(method, request_uri)
      ["SIP/2.0", status_code, reason_phrase] ->
          StatusLine.build(String.to_integer(status_code), reason_phrase)
    end
  end

  defp do_parse_headers(headers) do
    Enum.reduce(headers, %{}, &do_parse_headers_internal/2)
  end

  defp do_parse_headers_internal(data, acc) do
    {header, value} = do_parse_header(data)
    Map.put(acc, header, Map.get(acc, header, []) ++ [value])
  end

  defp do_parse_header(data) do
    [header_string, value] = String.split(data, ~r{ *: *}, parts: 2)
    header = do_header_to_atom(header_string)
    {header, do_value_to_struct(header, value)}
  end

  defp do_header_to_atom(string) do
    string
    |> String.replace("-", "_")
    |> String.downcase()
    |> String.to_atom()
  end

  defp do_value_to_struct(header, string) do
    case header do
      _ -> %Sippet.Headers.Generic{value: string}
    end
  end
end
