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

  test "records assigns deltas after form validate events" do
    {:ok, view, _html} = live(build_conn(), "/form")
    replay_id = :sys.get_state(view.pid).socket.assigns._replay_id

    render_change(view, "validate", %{"name" => "He"})
    render_change(view, "validate", %{"name" => "Hel"})
    render_change(view, "validate", %{"name" => "Hello"})

    {:ok, active} = Store.get_active(replay_id)

    event_types = Enum.map(active.events, fn {_t, type, _p} -> type end)
    assert Enum.count(event_types, &(&1 == :event)) == 3

    assigns_events =
      active.events
      |> Enum.filter(fn {_, :assigns, _} -> true; _ -> false end)

    has_name =
      Enum.any?(assigns_events, fn {_, :assigns, payload} ->
        name = get_in(payload, [:delta, :name]) || get_in(payload, [:snapshot, :name])
        name != nil
      end)

    assert has_name, "Expected at least one assigns entry with :name"
  end

  test "form assigns are replayable via accumulated_assigns" do
    alias PhoenixReplay.Recording

    {:ok, view, _html} = live(build_conn(), "/form")
    replay_id = :sys.get_state(view.pid).socket.assigns._replay_id

    render_change(view, "validate", %{"name" => "Alice"})
    render_click(view, "submit", %{"name" => "Alice"})

    GenServer.stop(view.pid)
    Process.sleep(50)

    {:ok, recording} = Store.get_recording(replay_id)

    last_index = length(recording.events) - 1
    final_assigns = Recording.accumulated_assigns(recording, last_index)

    assert final_assigns[:name] == "Alice"
    assert final_assigns[:submitted] == true
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
end
