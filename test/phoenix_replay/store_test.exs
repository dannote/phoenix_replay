defmodule PhoenixReplay.StoreTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.{Recording, Store}
  alias PhoenixReplay.TestSupport

  defmodule FailingStorage do
    @behaviour PhoenixReplay.Storage

    def init(_opts), do: :ok
    def save(_recording, _opts), do: {:error, :failed}
    def get(_id, _opts), do: :error
    def list(_opts), do: []
    def delete(_id, _opts), do: :ok
    def clear(_opts), do: :ok
  end

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

  test "list_recording_summaries returns lightweight finalized recordings", %{
    id: id,
    recording: rec
  } do
    Store.start_recording(id, rec)
    Store.append_event(id, {50, :event, %{name: "click", params: %{}}})
    Store.finalize(id)

    summaries = Store.list_recording_summaries()
    assert Enum.any?(summaries, &(&1.id == id and &1.event_count == 2))
  end

  test "cleanup removes recordings past max count", %{recording: rec} do
    original_max = Application.get_env(:phoenix_replay, :max_recordings)
    original_age = Application.get_env(:phoenix_replay, :max_recording_age_ms)
    original_authorize = Application.get_env(:phoenix_replay, :authorize)

    on_exit(fn ->
      restore_env(:max_recordings, original_max)
      restore_env(:max_recording_age_ms, original_age)
      restore_env(:authorize, original_authorize)
    end)

    Application.delete_env(:phoenix_replay, :max_recording_age_ms)

    Application.put_env(:phoenix_replay, :authorize, fn recording ->
      recording.id in ["old", "new"]
    end)

    Store.clear_all()

    for {id, connected_at} <- [{"old", 1000}, {"new", 2000}] do
      rec = %{rec | id: id, connected_at: connected_at}
      Store.start_recording(id, rec)
      Store.append_event(id, {50, :event, %{name: "click", params: %{}}})
      Store.finalize(id)
    end

    Application.put_env(:phoenix_replay, :max_recordings, 1)
    assert :ok = Store.cleanup()

    assert Store.get_recording("old") == :error
    assert {:ok, _} = Store.get_recording("new")
  end

  test "cleanup removes recordings past max age", %{recording: rec} do
    original_age = Application.get_env(:phoenix_replay, :max_recording_age_ms)
    original_max = Application.get_env(:phoenix_replay, :max_recordings)
    original_authorize = Application.get_env(:phoenix_replay, :authorize)

    on_exit(fn ->
      restore_env(:max_recording_age_ms, original_age)
      restore_env(:max_recordings, original_max)
      restore_env(:authorize, original_authorize)
    end)

    Application.delete_env(:phoenix_replay, :max_recordings)

    Application.put_env(:phoenix_replay, :authorize, fn recording -> recording.id == "too-old" end)

    old = %{rec | id: "too-old", connected_at: 1}
    Store.start_recording(old.id, old)
    Store.append_event(old.id, {50, :event, %{name: "click", params: %{}}})
    Store.finalize(old.id)

    Application.put_env(:phoenix_replay, :max_recording_age_ms, 1)
    assert :ok = Store.cleanup()

    assert Store.get_recording("too-old") == :error
  end

  test "authorization filters recordings", %{id: id, recording: rec} do
    original_authorize = Application.get_env(:phoenix_replay, :authorize)

    on_exit(fn ->
      if original_authorize do
        Application.put_env(:phoenix_replay, :authorize, original_authorize)
      else
        Application.delete_env(:phoenix_replay, :authorize)
      end
    end)

    Store.start_recording(id, rec)
    Store.append_event(id, {50, :event, %{name: "click", params: %{}}})
    Store.finalize(id)

    Application.put_env(:phoenix_replay, :authorize, fn recording -> recording.id != id end)

    assert Store.get_recording(id) == :error
    refute Enum.any?(Store.list_recording_summaries(), &(&1.id == id))
  end

  test "finalize skips saving recordings with no user events", %{id: id, recording: rec} do
    Store.start_recording(id, rec)
    Store.append_event(id, {50, :assigns, %{delta: %{count: 1}}})
    {:ok, _} = Store.finalize(id)

    assert Store.get_recording(id) == :error
  end

  test "finalize keeps active recording when persistence fails", %{id: id, recording: rec} do
    original_storage = Application.get_env(:phoenix_replay, :storage)

    on_exit(fn ->
      if original_storage do
        Application.put_env(:phoenix_replay, :storage, original_storage)
      else
        Application.delete_env(:phoenix_replay, :storage)
      end
    end)

    Application.put_env(:phoenix_replay, :storage, FailingStorage)

    Store.start_recording(id, rec)
    Store.append_event(id, {50, :event, %{name: "click", params: %{}}})

    assert {:error, :failed} = Store.finalize(id)
    assert {:ok, active} = Store.get_active(id)
    assert active.id == id
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

    recording = TestSupport.assert_eventually(fn -> Store.get_recording(id) end)
    assert length(recording.events) == 2
  end

  defp restore_env(key, nil), do: Application.delete_env(:phoenix_replay, key)
  defp restore_env(key, value), do: Application.put_env(:phoenix_replay, key, value)
end
