defmodule PhoenixReplay.RecorderTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.Store

  @endpoint PhoenixReplay.TestEndpoint

  test "records mount, events, and assigns changes for a LiveView session" do
    {:ok, view, _html} = live(build_conn(), "/counter")

    # The LiveView should have started a recording
    assert %{_replay_id: replay_id} = :sys.get_state(view.pid).socket.assigns

    # Click increment a few times
    render_click(view, "inc")
    render_click(view, "inc")
    render_click(view, "dec")

    # Check active recording has events
    {:ok, active} = Store.get_active(replay_id)
    assert active.view == PhoenixReplay.TestLive.Counter

    # Events: mount assigns + (event + assigns_delta) * 3
    event_types = Enum.map(active.events, fn {_t, type, _payload} -> type end)
    assert :mount in event_types
    assert Enum.count(event_types, &(&1 == :event)) == 3

    # Kill the LiveView — should auto-finalize
    GenServer.stop(view.pid)
    Process.sleep(50)

    {:ok, recording} = Store.get_recording(replay_id)
    assert recording.id == replay_id
    assert length(recording.events) > 0

    assigns_events =
      Enum.filter(recording.events, fn {_t, type, _p} -> type == :assigns end)

    deltas = Enum.map(assigns_events, fn {_t, :assigns, %{delta: d}} -> d end)

    counts =
      Enum.flat_map(deltas, fn d -> if Map.has_key?(d, :count), do: [d.count], else: [] end)

    # Initial count 0, then inc→1, inc→2, dec→1
    assert counts == [0, 1, 2, 1]
  end

  test "does not record on static (disconnected) render" do
    conn = get(build_conn(), "/counter")
    assert html_response(conn, 200) =~ "count"
  end

  test "records assigns delta with intermediate values for each keystroke" do
    {:ok, view, _html} = live(build_conn(), "/form")
    replay_id = :sys.get_state(view.pid).socket.assigns._replay_id

    render_change(view, "validate", %{"name" => "H"})
    render_change(view, "validate", %{"name" => "He"})
    render_change(view, "validate", %{"name" => "Hel"})
    render_change(view, "validate", %{"name" => "Hell"})
    render_change(view, "validate", %{"name" => "Hello"})

    {:ok, active} = Store.get_active(replay_id)

    assert Enum.count(active.events, fn
             {_, :event, _} -> true
             _ -> false
           end) == 5

    name_values =
      active.events
      |> Enum.flat_map(fn
        {_, :assigns, %{delta: %{name: n}}} -> [n]
        {_, :assigns, %{snapshot: %{name: n}}} -> [n]
        _ -> []
      end)

    assert name_values == ["", "H", "He", "Hel", "Hell", "Hello"]
  end

  test "form assigns are replayable via accumulated_assigns at each event" do
    alias PhoenixReplay.Recording

    {:ok, view, _html} = live(build_conn(), "/form")
    replay_id = :sys.get_state(view.pid).socket.assigns._replay_id

    render_change(view, "validate", %{"name" => "A"})
    render_change(view, "validate", %{"name" => "Al"})
    render_change(view, "validate", %{"name" => "Alice"})
    render_click(view, "submit", %{"name" => "Alice"})

    GenServer.stop(view.pid)
    Process.sleep(50)

    {:ok, recording} = Store.get_recording(replay_id)

    validate_indices =
      recording.events
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {{_, :event, %{name: "validate"}}, i} -> [i]
        _ -> []
      end)

    replayed_names =
      Enum.map(validate_indices, fn i ->
        assigns = Recording.accumulated_assigns(recording, i + 1)
        assigns[:name]
      end)

    assert replayed_names == ["A", "Al", "Alice"]

    last_index = length(recording.events) - 1
    final = Recording.accumulated_assigns(recording, last_index)
    assert final[:name] == "Alice"
    assert final[:submitted] == true
  end

  test "accumulated_assigns works with snapshot events" do
    alias PhoenixReplay.Recording

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
    alias PhoenixReplay.Recording

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
end
