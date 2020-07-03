defmodule Ophion.TS6.Server do
  defstruct [
    :name,
    :sid,
    :description,
    :depth,
    :parent_sid,
    users: %{},
    servers: []
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

  def add_child(%Server{} = parent, %Server{} = child) do
    servers =
      if child.sid in parent.servers do
        parent.servers
      else
        parent.servers ++ [child.sid]
      end

    Map.put(parent, :servers, servers)
  end

  def delete_child(%Server{} = parent, %Server{} = child) do
    servers =
      parent.servers
      |> List.delete(child.sid)

    Map.put(parent, :servers, servers)
  end
end
