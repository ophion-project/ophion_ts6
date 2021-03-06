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

  alias Ophion.TS6.Server
  alias Ophion.TS6.User

  @moduledoc """
  Describes the internal state of a TS6 state machine.
  """

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

  @doc "Retrieves a server instance from the state by SID or name."
  def get_server(%__MODULE__{} = state, sid_or_name) do
    case state.global_servers[sid_or_name] do
      %Server{} = server ->
        server

      sid when is_binary(sid) ->
        get_server(state, sid)

      _ ->
        nil
    end
  end

  @doc "Retrieves a user instance from the state by UID or name."
  def get_user(%__MODULE__{} = state, uid_or_name) do
    case state.global_users[uid_or_name] do
      %User{} = user ->
        user

      uid when is_binary(uid) ->
        get_user(state, uid)

      _ ->
        nil
    end
  end

  @doc "Orphan a user from the global user list as well as its parent."
  def delete_user(%__MODULE__{} = state, %User{} = user) do
    with {:parent, %Server{} = parent} <- {:parent, get_server(state, user.parent_sid)} do
      parent =
        parent
        |> Server.delete_user(user)

      state =
        state
        |> put_server(parent)

      global_users =
        state.global_users
        |> Map.delete(user.uid)
        |> Map.delete(user.name)

      Map.put(state, :global_users, global_users)
    else
      {:parent, nil} ->
        Logger.warn("#{inspect(__MODULE__)}: could not find parent SID #{user.parent_sid} of user #{user.uid}/#{user.name}!!!")
    end
  end

  @doc "Orphan a server from the global server list as well as its parent."
  def delete_server(%__MODULE__{} = state, %Server{} = server) do
    with {:parent, %Server{} = parent} <- {:parent, get_server(state, server.parent_sid)} do
      # delete descendents
      state =
        Enum.reduce(server.servers, state, fn child_sid, state ->
          with %Server{} = server <- get_server(state, child_sid) do
            delete_server(state, server)
          end
        end)

      # delete attached users
      state =
        Enum.reduce(server.users, state, fn child_uid, state ->
          with %User{} = user <- get_user(state, child_uid) do
            delete_user(state, user)
          end
        end)

      # now delete the server from its parent
      parent =
        parent
        |> Server.delete_child(server)

      # update the state with the new parent
      state =
        state
        |> put_server(parent)

      # update the state with the new global_servers table
      global_servers =
        state.global_servers
        |> Map.delete(server.sid)
        |> Map.delete(server.name)

      Map.put(state, :global_servers, global_servers)
    else
      {:parent, nil} ->
        Logger.warn("#{inspect(__MODULE__)}: could not find parent SID #{server.parent_sid} of server #{server.sid}/#{server.name}!!!")
    end
  end

  @doc "Upserts a user, deleting any previous record associated with the UID.  Recommended over put_user/2."
  def upsert_user(%__MODULE__{} = state, %User{} = new_user) do
    with {:old_user, %User{} = old_user} <- {:old_user, get_user(state, new_user.uid)} do
      global_users =
        state.global_users
        |> Map.delete(old_user.uid)
        |> Map.delete(old_user.name)

      state =
        state
        |> Map.put(:global_users, global_users)

      put_user(state, new_user)
    else
      {:old_user, nil} ->
        put_user(state, new_user)
    end
  end

  def put_user(%__MODULE__{} = state, %User{} = user) do
    with {:parent, %Server{} = parent} <- {:parent, get_server(state, user.parent_sid)} do
      parent =
        parent
        |> Server.add_user(user)

      state =
        state
        |> put_server(parent)

      # update the state with the new global_users table
      global_users =
        state.global_users
        |> Map.put(user.uid, user)
        |> Map.put(user.name, user.uid)

      Map.put(state, :global_users, global_users)
    else
      {:parent, nil} ->
        Logger.warn("#{inspect(__MODULE__)}: could not find parent SID #{user.parent_sid} of user #{user.uid}/#{user.name}!!!")
    end
  end

  def put_server(%__MODULE__{} = state, %Server{parent_sid: nil} = root) do
    global_servers =
      state.global_servers
      |> Map.put(root.sid, root)
      |> Map.put(root.name, root.sid)

    state
    |> Map.put(:root, root)
    |> Map.put(:global_servers, global_servers)
  end

  def put_server(%__MODULE__{} = state, %Server{} = server) do
    with {:parent, %Server{} = parent} <- {:parent, get_server(state, server.parent_sid)} do
      parent =
        parent
        |> Server.add_child(server)

      state =
        state
        |> put_server(parent)

      # update the state with the new global_servers table
      global_servers =
        state.global_servers
        |> Map.put(server.sid, server)
        |> Map.put(server.name, server.sid)

      Map.put(state, :global_servers, global_servers)
    else
      {:parent, nil} ->
        Logger.warn("#{inspect(__MODULE__)}: could not find parent SID #{server.parent_sid} of server #{server.sid}/#{server.name}!!!")
    end
  end

  @doc "A convenience function which updates a server's parent and links it into the graph."
  def link_server(%__MODULE__{} = state, %Server{} = parent, %Server{} = child) do
    child =
      child
      |> Map.put(:depth, parent.depth + 1)
      |> Map.put(:parent_sid, parent.sid)

    state =
      state
      |> put_server(child)

    parent = get_server(state, parent.sid)
    child = get_server(state, child.sid)

    {:ok, state, parent, child}
  end

  @doc "A convenience function which unlinks a server from the graph."
  def unlink_server(%__MODULE__{} = state, %Server{} = target) do
    with {:parent, %Server{} = parent} <- {:parent, get_server(state, target.parent_sid)} do
      state =
        state
        |> delete_server(target)

      parent =
        state
        |> get_server(parent.sid)

      {:ok, state, parent}
    else
      {:parent, nil} ->
        Logger.warn("#{inspect(__MODULE__)}: could not find parent SID #{target.parent_sid} of server #{target.sid}/#{target.name}!!!")
    end
  end

  @doc "A convenience function which updates a user's parent and links it into the graph."
  def link_user(%__MODULE__{} = state, %Server{} = parent, %User{} = child) do
    child =
      child
      |> Map.put(:depth, parent.depth + 1)
      |> Map.put(:parent_sid, parent.sid)

    state =
      state
      |> upsert_user(child)

    parent = get_server(state, parent.sid)
    child = get_user(state, child.uid)

    {:ok, state, parent, child}
  end

  @doc "Generate a network burst as a series of Ophion messages."
  def burst(%__MODULE__{} = state) do
    Server.burst(state, state.root, state.password)
  end
end
