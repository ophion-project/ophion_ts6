defmodule Ophion.TS6.Base36 do
  use CustomBase, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

  @moduledoc """
  A custom integral type which represents a 64-bit TS6 UID.
  """
end

defmodule Ophion.TS6.UID do
  alias Ophion.TS6.Base36

  @moduledoc """
  UID generation.

  This implements the Agent pattern and returns a new UID every time
  it is called.  The PID of the agent is kept private.
  """

  @doc """
  Start an UID generator agent.

  A function which wraps the agent process is returned on success,
  otherwise an error.
  """
  def start_link(sid) when is_binary(sid) and byte_size(sid) == 3 do
    initial_uid = sid <> "AAAAAA"
    initial_number = Base36.decode!(initial_uid)

    {:ok, pid} = Agent.start_link(fn -> initial_number end)

    generator =
      fn ->
        Agent.get_and_update(pid, fn i ->
          {Base36.encode(i), i + 1}
        end)
      end

    {:ok, generator}
  end

  def start_link(_), do: {:error, :invalid_sid}
end
