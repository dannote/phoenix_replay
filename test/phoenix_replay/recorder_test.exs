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
    # No recordings should exist for static renders
  end
end
