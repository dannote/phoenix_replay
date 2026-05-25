defmodule PhoenixReplay.RouterTest do
  use ExUnit.Case, async: true

  test "phoenix_replay macro mounts dashboard routes" do
    routes = PhoenixReplay.TestRouter.__routes__()

    assert Enum.any?(
             routes,
             &(&1.path == "/replay/player.js" and &1.plug == PhoenixReplay.Assets)
           )

    assert live_route?(routes, "/replay", PhoenixReplay.Live.Index)
    assert live_route?(routes, "/replay/:id", PhoenixReplay.Live.Show)
    assert live_route?(routes, "/replay/:id/frame", PhoenixReplay.Live.Frame)
  end

  defp live_route?(routes, path, module) do
    Enum.any?(routes, fn route ->
      route.path == path and match?({^module, :__live__, 0}, route.metadata.mfa)
    end)
  end
end
