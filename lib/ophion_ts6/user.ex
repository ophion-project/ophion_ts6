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
  def burst(%User{} = user, %Server{} = parent) do
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
