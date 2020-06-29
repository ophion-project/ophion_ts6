defmodule Ophion.TS6.UID.Test do
  use ExUnit.Case

  alias Ophion.TS6.UID

  test "it returns error for invalid SID" do
    {:error, :invalid_sid} = UID.start_link("1")
  end

  test "it successfully generates correct SIDs" do
    {:ok, gen} = UID.start_link("42X")

    assert "42XAAAAAA" == gen.()
    assert "42XAAAAAB" == gen.()
    assert "42XAAAAAC" == gen.()
    assert "42XAAAAAD" == gen.()
  end
end
