defmodule Sippet.Transport do
  alias Sippet.Message, as: Message

  def start_link() do
    schedulers_online = System.schedulers_online()
    Registry.start_link(:unique, __MODULE__,
                        partitions: schedulers_online)
  end

  @doc """
  Get a transport suitable to send the message.
  """
  @spec get_transport(%Message{}) :: pid
  def get_transport(%Message{headers: %{via: via}}) do
    {_version, protocol, {host, port}, _params} = via
    name = {protocol, host, port}
    case Registry.lookup(__MODULE__, name) do
      [{_parent_pid, child_pid}] ->
        child_pid
      [] ->
        {module, _new_args} =
          Application.get_env(:sippet, __MODULE__)
            |> Map.get(protocol)

        {:ok, child_pid} = apply(module, :start_child, [host, port])
        child_pid
    end
  end

  @doc """
  Sends a message to the given transport.
  """
  @spec send(pid, %Message{}) :: :ok
  def send(transport, %Message{} = message),
    do: GenServer.cast(transport, {:send, message})

  @doc """
  Whether this transport is reliable (stream-based).
  """
  @spec reliable(pid) :: boolean
  def reliable(transport),
    do: GenServer.call(transport, :reliable)
end
