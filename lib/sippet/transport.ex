defmodule Sippet.Transport do
  alias Sippet.Message, as: Message

  @type remote_address :: binary
  @type remote_port :: integer
  @type transport :: pid
  @type message :: %Message{}

  @doc """
  Starts a child process connected to the given destination.
  """
  @callback start_child(remote_address, remote_port, opts :: keyword) :: pid

  @doc """
  Sends a message to the given transport.
  """
  @callback send(transport, message) :: :ok

  @doc """
  Whether this transport is reliable (stream-based).
  """
  @callback reliable?() :: boolean
end

defmodule Sippet.Transport.Registry do
  alias Sippet.Message, as: Message

  def start_link() do
    schedulers_online = System.schedulers_online()
    Registry.start_link(:unique, __MODULE__,
                        partitions: schedulers_online)
  end

  defp do_get_transport(%Message{headers: %{via: via}}) do
    {_version, protocol, {host, port}, _params} = via
    name = {protocol, host, port}
    {module, _new_args} =
      Application.get_env(:sippet, __MODULE__)
      |> Map.get(protocol)

    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, child_pid}] ->
        {module, child_pid}
      [] ->
        opts = [name: via_tuple(module, name)]
        {:ok, child_pid} = apply(module, :start_child, [host, port, opts])
        {module, child_pid}
    end
  end

  defp via_tuple(module, name), do: {:via, Registry, {module, name}}

  def send(message) do
    {module, transport} = do_get_transport(message)
    apply(module, :send, [transport, message])
  end

  def reliable(message) do
    {module, _transport} = do_get_transport(message)
    apply(module, :reliable?, [])
  end
end
