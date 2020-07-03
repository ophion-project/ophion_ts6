defmodule Ophion.TS6.State.Test do
  use ExUnit.Case

  alias Ophion.TS6.Server
  alias Ophion.TS6.State

  @root_server %Server{name: "test.", sid: "0SV", description: "test server"}
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
      assert Map.has_key?(state.global_servers, "001")
    end

    test "basic - it can add a nested server" do
      peer_server = %Server{name: "peer.", sid: "001"}

      {:ok, state, root_server, peer_server} =
        @root_state
        |> State.link_server(@root_server, peer_server)

      assert peer_server.parent_sid == "0SV"
      assert "001" in root_server.servers
      assert Map.has_key?(state.global_servers, "001")

      nested_server = %Server{name: "nested.", sid: "002"}

      {:ok, state, peer_server, nested_server} =
        state
        |> State.link_server(peer_server, nested_server)

      assert nested_server.parent_sid == "001"
      assert "002" in peer_server.servers
      assert Map.has_key?(state.global_servers, "002")
    end

    test "basic - it can add a nested server 2 levels deep" do
      peer_server = %Server{name: "peer.", sid: "001"}

      {:ok, state, root_server, peer_server} =
        @root_state
        |> State.link_server(@root_server, peer_server)

      assert peer_server.parent_sid == "0SV"
      assert "001" in root_server.servers
      assert Map.has_key?(state.global_servers, "001")

      nested_server = %Server{name: "nested.", sid: "002"}

      {:ok, state, peer_server, nested_server} =
        state
        |> State.link_server(peer_server, nested_server)

      assert nested_server.parent_sid == "001"
      assert "002" in peer_server.servers
      assert Map.has_key?(state.global_servers, "002")

      second_nested_server = %Server{name: "second-nested.", sid: "003"}

      {:ok, state, nested_server, second_nested_server} =
        state
        |> State.link_server(nested_server, second_nested_server)

      assert second_nested_server.parent_sid == "002"
      assert "003" in nested_server.servers
      assert Map.has_key?(state.global_servers, "003")
    end

    test "basic - it properly orphans children servers" do
      peer_server = %Server{name: "peer.", sid: "001"}

      {:ok, state, root_server, peer_server} =
        @root_state
        |> State.link_server(@root_server, peer_server)

      assert peer_server.parent_sid == "0SV"
      assert "001" in root_server.servers
      assert Map.has_key?(state.global_servers, "001")

      nested_server = %Server{name: "nested.", sid: "002"}

      {:ok, state, peer_server, nested_server} =
        state
        |> State.link_server(peer_server, nested_server)

      assert nested_server.parent_sid == "001"
      assert "002" in peer_server.servers
      assert Map.has_key?(state.global_servers, "002")

      second_nested_server = %Server{name: "second-nested.", sid: "003"}

      {:ok, state, nested_server, second_nested_server} =
        state
        |> State.link_server(nested_server, second_nested_server)

      assert second_nested_server.parent_sid == "002"
      assert "003" in nested_server.servers
      assert Map.has_key?(state.global_servers, "003")

      {:ok, state, root_server} =
        state
        |> State.unlink_server(peer_server)

      assert "001" not in root_server.servers
      assert !Map.has_key?(state.global_servers, "002")
      assert !Map.has_key?(state.global_servers, "003")
    end
  end

  describe "bursting -" do
    test "it properly describes a nested topology" do
      peer_server = %Server{name: "peer.", sid: "001", description: "peer server"}

      {:ok, state, _root_server, peer_server} =
        @root_state
        |> State.link_server(@root_server, peer_server)

      nested_server = %Server{name: "nested.", sid: "002", description: "first nested server"}

      {:ok, state, _peer_server, nested_server} =
        state
        |> State.link_server(peer_server, nested_server)

      second_nested_server = %Server{name: "second-nested.", sid: "003", description: "second nested server"}

      {:ok, state, _nested_server, _second_nested_server} =
        state
        |> State.link_server(nested_server, second_nested_server)

      messages = State.burst(state)

      assert length(messages) == 6

      IO.puts(messages |> Enum.map(fn x ->
        {:ok, message} = Ophion.IRCv3.compose(x)
        message
      end) |> Enum.join(""))
    end
  end
end
