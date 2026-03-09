defmodule PhoenixReplayTest do
  use ExUnit.Case, async: true

  test "module exists" do
    assert is_list(PhoenixReplay.module_info(:attributes))
  end
end
