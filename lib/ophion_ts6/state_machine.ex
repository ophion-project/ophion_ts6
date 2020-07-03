defmodule Ophion.TS6.StateMachine do
  require Logger

  use GenServer

  alias Ophion.IRCv3.Message
  alias Ophion.TS6.Server
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

  def process(pid, messages) when is_binary(messages) do
    messages
    |> String.split("\n")
    |> Enum.each(fn msg ->
      {:ok, parsed} =
        msg
        |> String.trim()
        |> Ophion.IRCv3.parse()

      process(pid, parsed)
    end)
  end

  @doc """
  Attaches a command receiver callback at runtime.
  """
  def attach_command(pid, command, receiver) do
    GenServer.cast(pid, {:attach, command, receiver})
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

  @doc """
  Fetch the current state from the state machine.
  """
  def fetch(pid) do
    GenServer.call(pid, {:fetch})
  end

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

  def handle_cast({:attach, command, receiver}, %State{} = state) do
    with %State{} = new_state <- State.attach_command(state, command, receiver) do
      {:noreply, new_state}
    end
  end

  defp handle_message(%State{} = state, %Message{} = message) do
    Logger.debug("#{inspect(__MODULE__)}: processing #{inspect(message)} @#{inspect(self())}")

    state =
      (state.commands[message.verb] || [])
      |> Enum.reduce_while(state, fn callee, state ->
        callee.(state, message)
      end)

    {:ok, state}
  end

  def handle_call({:fetch}, _from, %State{} = state) do
    {:reply, state, state}
  end

  def handle_call({:burst, _excluding}, _from, %State{} = state) do
    messages =
      state.root
      |> Server.burst(state.password)
      |> Enum.map(&Ophion.IRCv3.compose/1)
      |> Enum.join("")

    {:reply, messages}
  end
end
