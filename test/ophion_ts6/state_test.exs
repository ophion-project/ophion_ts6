defmodule Ophion.TS6.State.Test do
  use ExUnit.Case

  alias Ophion.TS6.Server
  alias Ophion.TS6.State

  @root_server %Server{name: "test.", sid: "0SV"}
  @root_state %State{name: "test.", sid: "0SV", password: "password"}
              |> State.put_server(@root_server)

  describe "server tree -" do
    test "basic - it can add a peer server" do
      peer_server = %Server{name: "peer.", sid: "001"}

      {:ok, state, root_server, peer_server} =
        @root_state
        |> State.link_server(@root_server, peer_server)

      assert peer_server.parent_sid == "0SV"
      assert "001" in root_server.servers
    end
  end
end
