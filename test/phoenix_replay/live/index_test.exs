defmodule PhoenixReplay.Live.IndexTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Recording, Store}

  @endpoint PhoenixReplay.TestEndpoint

  setup do
    Store.clear_all()
    on_exit(fn -> Store.clear_all() end)

    recording = %Recording{
      id: "index-test-rec",
      view: PhoenixReplay.TestLive.Counter,
      url: "http://localhost/counter",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {1000, :event, %{name: "inc", params: %{}}},
        {1100, :assigns, %{delta: %{count: 1}}}
      ]
    }

    PhoenixReplay.Storage.backend().save(recording, PhoenixReplay.Storage.storage_opts())

    %{recording: recording}
  end

  test "renders stored recordings", %{recording: recording} do
    {:ok, _view, html} = live(build_conn(), "/replay")

    assert html =~ "PhoenixReplay.TestLive.Counter"
    assert html =~ String.slice(recording.id, 0..7)
    assert html =~ "3 events"
  end

  test "renders empty state when there are no recordings" do
    Store.clear_all()

    {:ok, _view, html} = live(build_conn(), "/replay")

    assert html =~ "No recordings yet"
  end

  test "refresh reloads recordings" do
    {:ok, view, _html} = live(build_conn(), "/replay")

    Store.clear_all()
    send(view.pid, :refresh)

    assert render(view) =~ "No recordings yet"
  end
end
