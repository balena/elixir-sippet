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
  alias Sippet.RequestLine, as: RequestLine
  alias Sippet.StatusLine, as: StatusLine

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
      false -> put_in(message, [:headers, header], [value])
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
  def put_new_lazy_header(message, header, fun) do
    case has_header?(message, header) do
      true -> message
      false -> put_in(message, [:headers, header], [fun.()])
    end
  end

  @doc """
  Puts the `value` under `header` on the `message`, as front element.

  If the parameter `value` is `nil`, then the empty list will be prefixed to
  the `header`.
  """
  @spec put_header_front(message, header, value) :: message
  def put_header_front(message, header, value) do
    head = case value do
      nil -> []
      _ -> [value]
    end
    put_in(message, [:headers, header],
        head ++ get_header(message, header, []))
  end

  @doc """
  Puts the `value` under `header` on the `message`, as last element.

  If the parameter `value` is `nil`, then the empty list will be appended to
  the `header`.
  """
  @spec put_header_back(message, header, value) :: message
  def put_header_back(message, header, value) do
    tail = case value do
      nil -> []
      _ -> [value]
    end
    put_in(message, [:headers, header],
        get_header(message, header, []) ++ tail)
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
      values -> case values do
        [_] -> delete_header(message, header)
        [_|tail] -> put_in(message, [:headers, header], tail)
      end
    end
  end

  @doc """
  Deletes the last value of `header` in `message`.
  """
  @spec delete_header_back(message, header) :: message
  def delete_header_back(message, header) do
    case get_header(message, header) do
      nil -> message
      values -> case values do
        [_] -> delete_header(message, header)
        values -> put_in(message, [:headers, header],
            List.delete(values, List.last(values)))
      end
    end
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
  def update_header(message, header, [initial], fun)
      when is_function(fun, 1) do
    put_in(message, [:headers, header],
        Map.update(message.headers, header, initial, fun))
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
           values -> List.delete(values, List.last(values))
             ++ fun.(List.last(values))
        end)
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
    {get, put_in(message, [:headers], new_headers)}
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
      [] -> {default, put_in(message, [:headers, header], new_headers)}
      [value] -> {value, put_in(message, [:headers, header], new_headers)}
      [head|tail] -> {head, put_in(message, [:headers, header], tail)}
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
    case values do
      [] -> {default, put_in(message, [:headers, header], new_headers)}
      [value] -> {value, put_in(message, [:headers, header], new_headers)}
      values -> {List.last(values), put_in(message, [:headers, header],
          List.delete(values, List.last(values)))}
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
    {get, put_in(message, [:headers], new_headers)}
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
    {get, put_in(message, [:headers], new_headers)}
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
    {get, put_in(message, [:headers], new_headers)}
  end

  defp do_get_and_update_header_back([], fun) do
    case fun.(nil) do
      {get, value} -> {get, [value]}
      :pop -> :pop
    end
  end

  defp do_get_and_update_header_back(values, fun) do
    last = List.last(values)
    case fun.(last) do
      {get, new_value} -> {get, List.delete(values, last) ++ [new_value]}
      :pop -> {last, List.delete(values, last)}
    end
  end

end
