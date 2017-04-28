defmodule Sippet.Transactions.Supervisor do
  @moduledoc false

  use Supervisor

  import Sippet.Transactions.Registry

  alias Sippet.Message, as: Message
  alias Sippet.Message.RequestLine, as: RequestLine
  alias Sippet.Transactions, as: Transactions

  @type request :: Message.request

  @doc false
  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Starts a client transaction.
  """
  @spec start_client(Transactions.Client.Key.t, request) ::
    Supervisor.on_start_child
  def start_client(%Transactions.Client.Key{} = key,
      %Message{start_line: %RequestLine{}} = outgoing_request) do
    module =
      case key.method do
        :invite -> Transactions.Client.Invite
        _otherwise -> Transactions.Client.NonInvite
      end

    initial_data = Transactions.Client.State.new(outgoing_request, key)
    Supervisor.start_child(__MODULE__, [module, initial_data,
                           [name: via_tuple(key)]])
  end

  @doc """
  Starts a server transaction.
  """
  @spec start_server(Transactions.Server.Key.t, request) ::
    Supervisor.on_start_child
  def start_server(%Transactions.Server.Key{} = key,
      %Message{start_line: %RequestLine{}} = incoming_request) do
    module =
      case key.method do
        :invite -> Transactions.Server.Invite
        _otherwise -> Transactions.Server.NonInvite
      end

    initial_data = Transactions.Server.State.new(incoming_request, key)
    Supervisor.start_child(__MODULE__, [module, initial_data,
                           [name: via_tuple(key)]])
  end

  @doc false
  def init([]) do
    children = [worker(GenStateMachine, [], restart: :transient)]
    options = [strategy: :simple_one_for_one]
    supervise(children, options)
  end
end
