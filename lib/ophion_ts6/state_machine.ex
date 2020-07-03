defmodule Ophion.TS6.State do
  require Logger

  defstruct [
    :name,
    :sid,
    :uid_generator,
    :connecting_server,
    :root,
    capabs: ["IE", "EX", "QS", "IRCX", "EUID"],
    required_capabs: ["IE", "EX", "QS", "EUID"],
    global_users: %{},
    global_clients: %{},
    channels: %{},
    commands: %{}
  ]

  def validate(%__MODULE__{name: nil}), do: {:error, {:invalid_state, :invalid_name}}
  def validate(%__MODULE__{sid: nil}), do: {:error, {:invalid_state, :invalid_sid}}
  def validate(_), do: :ok

  def attach_command(%__MODULE__{} = state, command, receiver) do
    Logger.debug("#{inspect(__MODULE__)}: attaching #{inspect(receiver)} to #{command}")

    with receivers <- (state.commands[command] || []) ++ [receiver],
         commands <- Map.put(state.commands, command, receivers),
         new_state <- Map.put(state, :commands, commands) do
      new_state
    end
  end
end

defmodule Ophion.TS6.User do
  defstruct [
    :name,
    :depth,
    :ts,
    :umode,
    :username,
    :hostname,
    :ip,
    :realhost,
    :account,
    :realname
  ]

  alias Ophion.IRCv3.Message
  alias Ophion.TS6.User
  alias Ophion.TS6.Server

  @moduledoc "A type describing a user on a TS6 network."

  @doc "Generate an `EUID` %Ophion.IRCv3.Message{} describing the user."
  def burst(%User{} = user, %__MODULE__{} = parent) do
    %Message{
      source: parent.sid,
      verb: "EUID",
      params: [
        user.name,
        user.depth |> Integer.to_string(),
        user.ts |> Integer.to_string(),
        user.umode,
        user.username,
        user.hostname,
        user.ip,
        user.realhost,
        user.account,
        user.realname
      ]
    }
  end
end

defmodule Ophion.TS6.Server do
  defstruct [
    :name,
    :sid,
    :description,
    :depth,
    users: %{},
    servers: %{}
  ]

  alias Ophion.IRCv3.Message
  alias Ophion.TS6.User
  alias Ophion.TS6.Server

  defp burst_children(%Server{} = parent) do
    uid_messages =
      parent.users
      |> Enum.map(fn %User{} = u ->
        User.burst(u, parent)
      end)

    leaf_messages =
      parent.servers
      |> Enum.map(fn %Server{} = s ->
        Server.burst(parent, s)
      end)

    uid_messages ++ leaf_messages
  end

  def burst(%Server{} = parent, %Server{} = child) do
    sid_message = %Message{
      source: parent.sid,
      verb: "SID",
      params: [
        child.name,
        child.depth |> Integer.to_string(),
        child.sid,
        child.description
      ]
    }

    [sid_message] ++ burst_children(child)
  end

  def burst(%Server{} = root, password) when is_binary(password) do
    pass_message = %Message{
      verb: "PASS",
      params: [
        password,
        "TS",
        "6",
        root.sid
      ]
    }

    # XXX: Use configured capabilities.
    capab_message = %Message{
      verb: "CAPAB",
      params: ["QS", "IE", "EX", "ENCAP", "IRCX", "EUID"]
    }

    server_message = %Message{
      verb: "SERVER",
      params: [
        root.name,
        root.depth |> Integer.to_string(),
        root.description
      ]
    }

    [pass_message, capab_message, server_message] ++ burst_children(root)
  end
end

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
      |> Server.burst()
      |> Enum.map(&Ophion.IRCv3.compose/1)
      |> Enum.join("")

    {:reply, messages}
  end
end
