defmodule Ophion.TS6.State do
  require Logger

  defstruct [
    :name,
    :sid,
    :uid_generator,
    :connecting_server,
    :root,
    :password,
    capabs: ["IE", "EX", "QS", "IRCX", "EUID"],
    required_capabs: ["IE", "EX", "QS", "EUID"],
    global_users: %{},
    global_servers: %{},
    channels: %{},
    commands: %{}
  ]

  def validate(%__MODULE__{name: nil}), do: {:error, {:invalid_state, :invalid_name}}
  def validate(%__MODULE__{sid: nil}), do: {:error, {:invalid_state, :invalid_sid}}
  def validate(%__MODULE__{password: nil}), do: {:error, {:invalid_state, :invalid_password}}
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
