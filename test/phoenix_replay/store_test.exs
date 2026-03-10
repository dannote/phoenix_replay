defmodule PhoenixReplay.StoreTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.{Recording, Store}

  setup do
    id = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    recording = %Recording{
      id: id,
      view: SomeLive,
      url: "http://localhost:4000/",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [{0, :mount, %{assigns: %{count: 0}}}]
    }

    %{id: id, recording: recording}
  end

  test "start_recording stores metadata in ETS", %{id: id, recording: rec} do
    Store.start_recording(id, rec)
    assert {:ok, active} = Store.get_active(id)
    assert active.id == id
    assert active.view == SomeLive
  end

  test "append_event adds events retrievable via get_active", %{id: id, recording: rec} do
    Store.start_recording(id, rec)

    Store.append_event(id, {100, :event, %{name: "click", params: %{}}})
    Store.append_event(id, {200, :event, %{name: "submit", params: %{"name" => "Dan"}}})

    {:ok, active} = Store.get_active(id)
    # 1 mount event from recording + 2 appended
    assert length(active.events) == 3
    assert {100, :event, %{name: "click"}} = Enum.at(active.events, 1)
    assert {200, :event, %{name: "submit"}} = Enum.at(active.events, 2)
  end

  test "finalize moves recording to completed table", %{id: id, recording: rec} do
    Store.start_recording(id, rec)
    Store.append_event(id, {50, :event, %{name: "click", params: %{}}})

    assert {:ok, finalized} = Store.finalize(id)
    assert length(finalized.events) == 2

    assert {:ok, ^finalized} = Store.get_recording(id)
    assert Store.get_active(id) == :error
  end

  test "finalize returns :error for unknown id" do
    assert Store.finalize("nonexistent") == :error
  end

  test "max_events is enforced", %{id: id, recording: rec} do
    Application.put_env(:phoenix_replay, :max_events, 5)

    Store.start_recording(id, rec)

    for i <- 1..10 do
      Store.append_event(id, {i * 10, :event, %{name: "e#{i}"}})
    end

    {:ok, active} = Store.get_active(id)
    # 1 mount + 5 max appended
    assert length(active.events) == 6
  after
    Application.delete_env(:phoenix_replay, :max_events)
  end

  test "list_recordings returns finalized recordings", %{id: id, recording: rec} do
    Store.start_recording(id, rec)
    Store.append_event(id, {50, :event, %{name: "click", params: %{}}})
    Store.finalize(id)

    recordings = Store.list_recordings()
    assert Enum.any?(recordings, &(&1.id == id))
  end

  test "finalize skips saving recordings with no user events", %{id: id, recording: rec} do
    Store.start_recording(id, rec)
    Store.append_event(id, {50, :assigns, %{delta: %{count: 1}}})
    {:ok, _} = Store.finalize(id)

    assert Store.get_recording(id) == :error
  end

  test "auto-finalize on process exit" do
    id = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    test_pid = self()

    rec = %Recording{
      id: id,
      view: SomeLive,
      url: nil,
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [{0, :mount, %{assigns: %{}}}]
    }

    pid =
      spawn(fn ->
        Store.start_recording(id, rec)
        Store.append_event(id, {10, :event, %{name: "click", params: %{}}})
        send(test_pid, :recording_started)
        # Keep alive until told to exit
        receive do
          :exit -> :ok
        end
      end)

    assert_receive :recording_started, 1000

    ref = Process.monitor(pid)
    send(pid, :exit)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

    # Give the Store time to handle the :DOWN message
    Process.sleep(50)

    assert {:ok, recording} = Store.get_recording(id)
    assert length(recording.events) == 2
  end
end
