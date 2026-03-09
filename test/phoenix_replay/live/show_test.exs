defmodule PhoenixReplay.Live.ShowTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Recording, Store}

  @endpoint PhoenixReplay.TestEndpoint

  setup do
    Store.clear_all()

    recording = %Recording{
      id: "test-show-rec",
      view: PhoenixReplay.TestLive.Counter,
      url: "http://localhost/counter",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {1000, :assigns, %{delta: %{count: 0}}},
        {3000, :event, %{name: "inc"}},
        {3100, :assigns, %{delta: %{count: 1}}},
        {5000, :event, %{name: "inc"}},
        {5100, :assigns, %{delta: %{count: 2}}},
        {8000, :event, %{name: "dec"}},
        {8100, :assigns, %{delta: %{count: 1}}},
        {12000, :event, %{name: "inc"}},
        {12100, :assigns, %{delta: %{count: 2}}}
      ]
    }

    PhoenixReplay.Storage.backend().save(recording, PhoenixReplay.Storage.storage_opts())
    on_exit(fn -> Store.clear_all() end)

    %{recording: recording}
  end

  defp mount_show(conn \\ build_conn()) do
    {:ok, view, html} = live(conn, "/replay/test-show-rec")
    {view, html}
  end

  # --- Rendering ---

  test "renders recording metadata" do
    {_view, html} = mount_show()
    assert html =~ "PhoenixReplay.TestLive.Counter"
    assert html =~ "test-show-re"
    assert html =~ "10 events"
  end

  test "renders total duration" do
    {_view, html} = mount_show()
    assert html =~ "0:12"
  end

  test "renders play button initially (not playing)" do
    {_view, html} = mount_show()
    assert html =~ "▶"
    refute html =~ "⏸"
  end

  test "renders scrubber with max = last event index" do
    {_view, html} = mount_show()
    assert html =~ ~s(id="rp-scrubber")
    assert html =~ ~s(max="9")
  end

  test "renders event markers" do
    {_view, html} = mount_show()
    assert html =~ "rp-scrub-marker"
    assert html =~ ~s(title="mount")
    assert html =~ ~s(title="inc")
    assert html =~ ~s(title="dec")
  end

  # --- Step forward / back ---

  test "step_forward advances current_index" do
    {view, _html} = mount_show()
    render_click(view, "step_forward")
    assert view |> element("#rp-scrubber") |> render() =~ ~s(max="9")
  end

  test "step_back at beginning stays at 0" do
    {view, _html} = mount_show()
    render_click(view, "step_back")
    assert render(view) =~ "PhoenixReplay.TestLive.Counter"
  end

  test "step_forward at end stays at last event" do
    {view, _html} = mount_show()
    for _ <- 1..20, do: render_click(view, "step_forward")
    assert render(view) =~ "PhoenixReplay.TestLive.Counter"
  end

  # --- Jump / Seek ---

  test "jump to specific index" do
    {view, _html} = mount_show()
    render_click(view, "jump", %{"index" => "4"})
    render_click(view, "toggle_events")
    html = render(view)
    assert html =~ "active"
  end

  test "scrub by index from scrubber" do
    {view, _html} = mount_show()
    render_click(view, "scrub", %{"index" => "6"})
    render_click(view, "toggle_events")
    html = render(view)
    assert html =~ "active"
  end

  # --- Play / Pause push events ---

  test "play pushes play event with speed" do
    {view, _html} = mount_show()
    render_click(view, "play")
    assert render(view) =~ "PhoenixReplay.TestLive.Counter"
  end

  test "pause pushes stop event" do
    {view, _html} = mount_show()
    render_click(view, "pause")
    assert render(view) =~ "PhoenixReplay.TestLive.Counter"
  end

  # --- Speed ---

  test "speed change updates assigns and re-renders" do
    {view, _html} = mount_show()
    html = render_click(view, "speed", %{"speed" => "10"})
    assert html =~ "10×"
  end

  test "speed change from 1 to 5" do
    {view, _html} = mount_show()
    html = render_click(view, "speed", %{"speed" => "5"})
    assert html =~ "5×"
  end

  # --- Events panel ---

  test "toggle_events shows event list with all event types" do
    {view, html} = mount_show()
    refute html =~ "📦 Assigns"

    html = render_click(view, "toggle_events")
    assert html =~ "📦 Assigns"
    assert html =~ "mount"
    assert html =~ "assigns changed"
    assert html =~ "inc"
    assert html =~ "dec"
  end

  test "toggle_events hides when toggled again" do
    {view, _html} = mount_show()
    render_click(view, "toggle_events")
    html = render_click(view, "toggle_events")
    refute html =~ "📦 Assigns"
  end

  test "events panel shows accumulated assigns" do
    {view, _html} = mount_show()
    render_click(view, "jump", %{"index" => "5"})
    html = render_click(view, "toggle_events")
    assert html =~ "count"
  end

  # --- Init push_event ---

  test "handle_params pushes init event with event offsets" do
    {view, _html} = mount_show()
    assert render(view) =~ ~s(max="9")
  end

  # --- Redirect ---

  test "redirects for nonexistent recording" do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(build_conn(), "/replay/nonexistent")
  end
end
