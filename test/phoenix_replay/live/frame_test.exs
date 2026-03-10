defmodule PhoenixReplay.Live.FrameTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Recording, Store}

  @endpoint PhoenixReplay.TestEndpoint

  setup do
    Store.clear_all()
    on_exit(fn -> Store.clear_all() end)
  end

  defp save_recording(recording) do
    PhoenixReplay.Storage.backend().save(recording, PhoenixReplay.Storage.storage_opts())
  end

  test "renders form values from assigns at each replay step" do
    recording = %Recording{
      id: "frame-form-test",
      view: PhoenixReplay.TestLive.Form,
      url: "http://localhost/form",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: %{name: "", submitted: false}}},
        {100, :assigns, %{delta: %{name: "", submitted: false}}},
        {1000, :event, %{name: "validate", params: %{"name" => "H"}}},
        {1001, :assigns, %{delta: %{name: "H"}}},
        {2000, :event, %{name: "validate", params: %{"name" => "He"}}},
        {2001, :assigns, %{delta: %{name: "He"}}},
        {3000, :event, %{name: "validate", params: %{"name" => "Hello"}}},
        {3001, :assigns, %{delta: %{name: "Hello"}}}
      ]
    }

    save_recording(recording)

    {:ok, view, html} = live(build_conn(), "/replay/frame-form-test/frame?index=1")
    assert html =~ ~s(value="")

    send(view.pid, {:replay_jump, 3})
    html = render(view)
    assert html =~ ~s(value="H")

    send(view.pid, {:replay_jump, 5})
    html = render(view)
    assert html =~ ~s(value="He")

    send(view.pid, {:replay_jump, 7})
    html = render(view)
    assert html =~ ~s(value="Hello")
  end

  test "renders counter values at each replay step" do
    recording = %Recording{
      id: "frame-counter-test",
      view: PhoenixReplay.TestLive.Counter,
      url: "http://localhost/counter",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {100, :assigns, %{delta: %{count: 0}}},
        {1000, :event, %{name: "inc", params: %{}}},
        {1001, :assigns, %{delta: %{count: 1}}},
        {2000, :event, %{name: "inc", params: %{}}},
        {2001, :assigns, %{delta: %{count: 2}}},
        {3000, :event, %{name: "dec", params: %{}}},
        {3001, :assigns, %{delta: %{count: 1}}}
      ]
    }

    save_recording(recording)

    {:ok, view, html} = live(build_conn(), "/replay/frame-counter-test/frame?index=1")
    assert html =~ ">0</span>"

    send(view.pid, {:replay_jump, 3})
    assert render(view) =~ ">1</span>"

    send(view.pid, {:replay_jump, 5})
    assert render(view) =~ ">2</span>"

    send(view.pid, {:replay_jump, 7})
    assert render(view) =~ ">1</span>"
  end

  test "snapshot replaces all assigns for frame rendering" do
    recording = %Recording{
      id: "frame-snapshot-test",
      view: PhoenixReplay.TestLive.Counter,
      url: "http://localhost/counter",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {100, :assigns, %{delta: %{count: 0}}},
        {1000, :event, %{name: "inc", params: %{}}},
        {2000, :event, %{name: "inc", params: %{}}},
        {3000, :assigns, %{snapshot: %{count: 5}}}
      ]
    }

    save_recording(recording)

    {:ok, view, _html} = live(build_conn(), "/replay/frame-snapshot-test/frame?index=1")

    send(view.pid, {:replay_jump, 4})
    assert render(view) =~ ">5</span>"
  end
end
