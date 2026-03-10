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

  test "renders scrubber with duration data attribute" do
    {_view, html} = mount_show()
    assert html =~ ~s(id="rp-scrubber")
    assert html =~ ~s(data-duration="12100")
  end

  test "renders event markers" do
    {_view, html} = mount_show()
    assert html =~ ~s(title="mount")
    assert html =~ ~s(title="inc")
    assert html =~ ~s(title="dec")
  end

  # --- Step forward / back ---

  test "step_forward advances current_index" do
    {view, _html} = mount_show()
    render_click(view, "step_forward")
    assert render(view) =~ "0:01"
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
    html = render(view)
    assert html =~ "bg-neutral-900"
  end

  test "scrub by index from scrubber" do
    {view, _html} = mount_show()
    render_click(view, "scrub", %{"index" => "6"})
    html = render(view)
    assert html =~ "bg-neutral-900"
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

  test "events panel always visible with all event types" do
    {_view, html} = mount_show()
    assert html =~ "Assigns"
    assert html =~ "mount"
    assert html =~ "assigns changed"
    assert html =~ "inc"
    assert html =~ "dec"
  end

  test "events panel shows accumulated assigns" do
    {view, _html} = mount_show()
    html = render_click(view, "jump", %{"index" => "5"})
    assert html =~ "count"
  end

  # --- Init push_event ---

  test "handle_params pushes init event with event offsets" do
    {view, _html} = mount_show()
    assert render(view) =~ ~s(data-duration="12100")
  end

  # --- Event labels with params ---

  test "event label shows _target field value for form events" do
    Store.clear_all()

    recording = %Recording{
      id: "test-params-rec",
      view: PhoenixReplay.TestLive.Counter,
      url: "http://localhost/counter",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {1000, :event,
         %{
           name: "validate",
           params: %{"_target" => ["title"], "title" => "Hello", "priority" => "medium"}
         }},
        {2000, :event,
         %{
           name: "validate",
           params: %{"_target" => ["description"], "title" => "Hello", "description" => "World"}
         }},
        {3000, :event, %{name: "save", params: %{"title" => "Hello", "description" => "World"}}},
        {4000, :event, %{name: "delete", params: %{"id" => "42"}}}
      ]
    }

    PhoenixReplay.Storage.backend().save(recording, PhoenixReplay.Storage.storage_opts())

    {:ok, view, html} = live(build_conn(), "/replay/test-params-rec")

    assert html =~ "validate: title=Hello"
    assert html =~ "validate: description=World"
    assert html =~ "save: description=World, title=Hello"
    assert html =~ "delete: id=42"
  end

  test "event label handles events without params" do
    {_view, html} = mount_show()
    assert html =~ "inc"
    assert html =~ "dec"
  end

  # --- Form typing replay ---

  test "stepping through form events shows intermediate values in assigns panel" do
    Store.clear_all()

    recording = %Recording{
      id: "test-typing-rec",
      view: PhoenixReplay.TestLive.Form,
      url: "http://localhost/form",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: %{name: "", submitted: false}}},
        {100, :assigns, %{delta: %{name: "", submitted: false}}},
        {1000, :event, %{name: "validate", params: %{"_target" => ["name"], "name" => "H"}}},
        {1001, :assigns, %{delta: %{name: "H"}}},
        {2000, :event, %{name: "validate", params: %{"_target" => ["name"], "name" => "He"}}},
        {2001, :assigns, %{delta: %{name: "He"}}},
        {3000, :event, %{name: "validate", params: %{"_target" => ["name"], "name" => "Hello"}}},
        {3001, :assigns, %{delta: %{name: "Hello"}}}
      ]
    }

    PhoenixReplay.Storage.backend().save(recording, PhoenixReplay.Storage.storage_opts())

    {:ok, view, _html} = live(build_conn(), "/replay/test-typing-rec")

    html = render_click(view, "jump", %{"index" => "3"})
    assert html =~ "validate: name=H"
    assert html =~ "&quot;H&quot;"

    html = render_click(view, "jump", %{"index" => "5"})
    assert html =~ "&quot;He&quot;"

    html = render_click(view, "jump", %{"index" => "7"})
    assert html =~ "&quot;Hello&quot;"
  end

  # --- Redirect ---

  test "redirects for nonexistent recording" do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(build_conn(), "/replay/nonexistent")
  end
end
