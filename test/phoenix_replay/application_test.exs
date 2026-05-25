defmodule PhoenixReplay.ApplicationTest do
  use ExUnit.Case, async: true

  test "starts supervised store and pubsub processes" do
    assert Process.whereis(PhoenixReplay.Store)
    assert Process.whereis(PhoenixReplay.PubSub)
  end
end
