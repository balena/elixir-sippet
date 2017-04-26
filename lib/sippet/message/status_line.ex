defmodule Sippet.Message.StatusLine do
  @moduledoc """
  A SIP Status-Line struct, composed by the SIP-Version, Status-Code and the
  Reason-Phrase.

  The `start_line` of responses are represented by this struct. The RFC 3261
  represents the Status-Line as:

      Status-Line  =  SIP-Version SP Status-Code SP Reason-Phrase CRLF

  The above `SIP-Version` is represented by a `{major, minor}` tuple, which
  assumes the value `{2, 0}` in standard implementations.

  The `Status-Code` is a 3-digit integer in the interval 100-699 indicating the
  outcome of an attempt to understand and satisfy a request.

  The `Reason-Phrase` is a binary representing a short textual description of
  the `Status-Code`.

  The `Status-Code` is intended for use by automata, whereas the
  `Reason-Phrase` is intended for the human user.
  """

  defstruct [
    status_code: nil,
    reason_phrase: nil,
    version: nil
  ]

  @type status_code :: 100..699

  @type version :: {integer, integer}

  @type t :: %__MODULE__{
    status_code: status_code,
    reason_phrase: binary,
    version: version
  }

  @default_status_codes %{
    100 => "Trying",
    180 => "Ringing",
    181 => "Call Is Being Forwarded",
    182 => "Queued",
    183 => "Session Progress",
    199 => "Early Dialog Terminated",
    200 => "OK",
    202 => "Accepted",
    204 => "No Notification",
    300 => "Multiple Choices",
    301 => "Moved Permanently",
    302 => "Moved Temporarily",
    305 => "Use Proxy",
    380 => "Alternative Service",
    400 => "Bad Request",
    401 => "Unauthorized",
    402 => "Payment Required",
    403 => "Forbidden",
    404 => "Not Found",
    405 => "Method Not Allowed",
    406 => "Not Acceptable",
    407 => "Proxy Authentication Required",
    408 => "Request Timeout",
    410 => "Gone",
    412 => "Conditional Request Failed",
    413 => "Request Entity Too Large",
    414 => "Request-URI Too Long",
    415 => "Unsupported Media Type",
    416 => "Unsupported URI Scheme",
    417 => "Unknown Resource-Priority",
    420 => "Bad Extension",
    421 => "Extension Required",
    422 => "Session Interval Too Small",
    423 => "Interval Too Brief",
    424 => "Bad Location Information",
    428 => "Use Identity Header",
    429 => "Provide Referrer Identity",
    430 => "Flow Failed",
    433 => "Anonymity Disallowed",
    436 => "Bad Identity-Info",
    437 => "Unsupported Certificate",
    438 => "Invalid Identity Header",
    439 => "First Hop Lacks Outbound Support",
    440 => "Max-Breadth Exceeded",
    469 => "Bad Info Package",
    470 => "Consent Needed",
    480 => "Temporarily Unavailable",
    481 => "Call/Transaction Does Not Exist",
    482 => "Loop Detected",
    483 => "Too Many Hops",
    484 => "Address Incomplete",
    485 => "Ambiguous",
    486 => "Busy Here",
    487 => "Request Terminated",
    488 => "Not Acceptable Here",
    489 => "Bad Event",
    491 => "Request Pending",
    493 => "Undecipherable",
    494 => "Security Agreement Required",
    500 => "Server Internal Error",
    501 => "Not Implemented",
    502 => "Bad Gateway",
    503 => "Service Unavailable",
    504 => "Server Time-out",
    505 => "Version Not Supported",
    513 => "Message Too Large",
    580 => "Precondition Failure",
    600 => "Busy Everywhere",
    603 => "Decline",
    604 => "Does Not Exist Anywhere",
    606 => "Not Acceptable"
  }

  @doc """
  Returns a Status-Line struct.

  The `reason_phrase` is obtained from default values.

  The function will throw an exception if the `status_code` is not in the valid
  range `100..699` or if the `status_code` does not have a default reason
  phrase.

  The version will assume the default value `{2, 0}`.

  ## Examples

      iex> Sippet.Message.StatusLine.new(400)
      %Sippet.Message.StatusLine{reason_phrase: "Bad Request", status_code: 400,
       version: {2, 0}}

  """
  @spec new(status_code) :: t | no_return
  def new(status_code) when is_integer(status_code),
    do: new(status_code, default_reason!(status_code))

  @doc """
  Creates a Status-Line struct using a given reason phrase.

  In this function, the `reason_phrase` can be anything the application wants.

  The function will throw an exception if the `status_code` is not in the valid
  range `100..699`.

  The version will assume the default value `{2, 0}`.

  ## Examples

      iex> Sippet.Message.StatusLine.new(499, "Foobar")
      %Sippet.Message.StatusLine{reason_phrase: "Foobar", status_code: 499,
       version: {2, 0}}

  """
  @spec new(status_code, reason_phrase :: binary) :: t
  def new(status_code, reason_phrase)
      when is_integer(status_code) and is_binary(reason_phrase) do
    %__MODULE__{
      status_code: do_raise_if_invalid(status_code),
      reason_phrase: reason_phrase,
      version: {2, 0}
    }
  end

  defp do_raise_if_invalid(status_code) do
    if status_code < 100 || status_code >= 700 do
      raise "invalid status code, got: #{inspect(status_code)}"
    else
      status_code
    end
  end

  @doc """
  Returns an integer representing the status code class in the range `[1, 6]`.

  ## Examples

      iex> alias Sippet.Message.StatusLine
      iex> StatusLine.new(202) |> StatusLine.status_code_class()
      2

  """
  @spec status_code_class(t) :: 1..6
  def status_code_class(%__MODULE__{status_code: status_code}) do
    div(status_code, 100)
  end

  @doc """
  Returns a binary representing the default reason phrase for the given
  `status_code`.

  If the `status_code` does not have a corresponding default reason phrase,
  returns `nil`.

  ## Examples

      iex> Sippet.Message.StatusLine.default_reason(202)
      "Accepted"
      iex> Sippet.Message.StatusLine.default_reason(499)
      nil

  """
  @spec default_reason(status_code) :: binary | nil
  def default_reason(status_code) do
    defaults = @default_status_codes
    if defaults |> Map.has_key?(status_code) do
      defaults[status_code]
    else
      nil
    end
  end

  @doc """
  Returns a binary representing the default reason phrase for the given
  `status_code`.

  If the `status_code` does not have a corresponding default reason phrase,
  throws an exception.

  ## Examples

      iex> Sippet.Message.StatusLine.default_reason!(202)
      "Accepted"
      iex> Sippet.Message.StatusLine.default_reason!(499)
      ** (ArgumentError) status code 499 does not have a default reason phrase

  """
  @spec default_reason!(status_code) :: binary | no_return
  def default_reason!(status_code) do
    case status_code |> do_raise_if_invalid() |> default_reason() do
      nil ->
        raise ArgumentError, "status code #{inspect status_code} " <>
                             "does not have a default reason phrase"
      reason_phrase ->
        reason_phrase
    end
  end

  @doc """
  Returns a binary which corresponds to the text representation of the given
  Status-Line.

  It does not includes an ending line CRLF.

  ## Examples

    iex> alias Sippet.StatusLine
    iex> StatusLine.new(202) |> StatusLine.to_string
    "SIP/2.0 202 Accepted"

  """
  @spec to_string(t) :: binary
  defdelegate to_string(value), to: String.Chars.Sippet.Message.StatusLine

  @doc """
  Returns an iodata which corresponds to the text representation of the given
  Status-Line.

  It does not includes an ending line CRLF.

  ## Examples

    iex> alias Sippet.StatusLine
    iex> StatusLine.new(202) |> StatusLine.to_iodata
    ["SIP/", "2", ".", "0", " ", "202", " ", "Accepted"]

  """
  @spec to_iodata(t) :: iodata
  def to_iodata(%Sippet.Message.StatusLine{version: {major, minor},
      status_code: status_code, reason_phrase: reason_phrase}) do
    ["SIP/", Integer.to_string(major), ".", Integer.to_string(minor),
      " ", Integer.to_string(status_code),
      " ", reason_phrase]
  end
end

defimpl String.Chars, for: Sippet.Message.StatusLine do
  alias Sippet.Message.StatusLine, as: StatusLine

  def to_string(%StatusLine{} = status_line) do
    status_line
    |> StatusLine.to_iodata()
    |> IO.iodata_to_binary
  end
end
