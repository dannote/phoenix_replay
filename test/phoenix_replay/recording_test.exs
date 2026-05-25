defmodule PhoenixReplay.RecordingTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording

  test "accumulated_assigns replays mount assigns and deltas" do
    recording = %Recording{
      id: "delta-test",
      view: SomeLive,
      url: nil,
      params: %{},
      session: %{},
      connected_at: 0,
      events: [
        {0, :mount, %{assigns: %{name: "", count: 0}}},
        {100, :event, %{name: "validate", params: %{"name" => "A"}}},
        {200, :assigns, %{delta: %{name: "A"}}},
        {300, :event, %{name: "inc", params: %{}}},
        {400, :assigns, %{delta: %{count: 1}}}
      ]
    }

    assert Recording.accumulated_assigns(recording, 0) == %{name: "", count: 0}
    assert Recording.accumulated_assigns(recording, 2) == %{name: "A", count: 0}
    assert Recording.accumulated_assigns(recording, 4) == %{name: "A", count: 1}
  end

  test "accumulated_assigns works with snapshot events" do
    recording = %Recording{
      id: "snap-test",
      view: SomeLive,
      url: nil,
      params: %{},
      session: %{},
      connected_at: 0,
      events: [
        {0, :mount, %{assigns: %{name: "", count: 0}}},
        {100, :event, %{name: "validate", params: %{"name" => "A"}}},
        {200, :event, %{name: "validate", params: %{"name" => "AB"}}},
        {300, :assigns, %{snapshot: %{name: "AB", count: 0}}},
        {400, :event, %{name: "inc", params: %{}}},
        {500, :assigns, %{delta: %{count: 1}}}
      ]
    }

    assert Recording.accumulated_assigns(recording, 0) == %{name: "", count: 0}
    assert Recording.accumulated_assigns(recording, 3) == %{name: "AB", count: 0}
    assert Recording.accumulated_assigns(recording, 5) == %{name: "AB", count: 1}
  end

  test "snapshot replaces all previous assigns, not merges" do
    recording = %Recording{
      id: "snap-replace",
      view: SomeLive,
      url: nil,
      params: %{},
      session: %{},
      connected_at: 0,
      events: [
        {0, :mount, %{assigns: %{a: 1, b: 2, c: 3}}},
        {100, :assigns, %{snapshot: %{a: 10, b: 20}}}
      ]
    }

    result = Recording.accumulated_assigns(recording, 1)
    assert result == %{a: 10, b: 20}
    refute Map.has_key?(result, :c)
  end

  test "non-assign events do not change accumulated assigns" do
    recording = %Recording{
      id: "ignore-events",
      view: SomeLive,
      url: nil,
      params: %{},
      session: %{},
      connected_at: 0,
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {100, :event, %{name: "inc", params: %{}}},
        {200, :handle_params, %{params: %{}, url: "/"}},
        {300, :info, %{}}
      ]
    }

    assert Recording.accumulated_assigns(recording, 3) == %{count: 0}
  end
end
