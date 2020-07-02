defmodule Ophion.TS6.State do
  defstruct [
    :name,
    :sid,
    :uid_generator,
    clients: %{},
    channels: %{},
    servers: %{}
  ]

  def validate(%__MODULE__{name: nil}), do: {:error, {:invalid_state, :invalid_name}}
  def validate(%__MODULE__{sid: nil}), do: {:error, {:invalid_state, :invalid_sid}}
  def validate(_), do: :ok
end

defmodule Ophion.TS6.StateMachine do
  use GenServer

  alias Ophion.IRCv3.Message
  alias Ophion.TS6.State
  alias Ophion.TS6.UID

  @doc """
  Starts a state machine.  Returns the PID for a state machine associated
  with a given state.
  """
  def start(%State{} = state) do
    with :ok <- State.validate(state) do
      GenServer.start(__MODULE__, state)
    else
      err -> err
    end
  end

  @doc """
  Advance the state machine by processing an incoming message.
  """
  def process(pid, %Message{} = message) do
    GenServer.cast(pid, {:process, message})
  end

  @doc """
  Generate a burst transaction which describes the current state machine.

  The `excluding` variable is the name of a leaf server that should be excluded
  from the burst.
  """
  def burst(pid, excluding) do
    GenServer.call(pid, {:burst, excluding})
  end
  def burst(pid), do: burst(pid, nil)

  # callbacks
  def init(%State{} = state) do
    # start the UID generator
    with {:ok, generator} <- UID.start_link(state.sid),
         state <- Map.put(state, :uid_generator, generator) do
      {:ok, state}
    end
  end

  def handle_cast({:process, message}, %State{} = state) do
    {:ok, state} =
      state
      |> handle_message(message)

    {:noreply, state}
  end

  defp handle_message(%State{} = state, %Message{} = message) do
    state =
      (state.listeners[message.verb] || [])
      |> Enum.reduce_while(state, fn callee, state ->
        callee.(state, message)
      end)

    {:ok, state}
  end

  # XXX: implement these
  def handle_call({:burst, _excluding}, %State{} = _state) do
    {:reply, "\r\n"}
  end
end