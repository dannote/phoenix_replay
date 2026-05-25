defmodule PhoenixReplay.Storage.EctoTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Storage.Ecto, as: EctoStorage

  defmodule Repo do
    use Ecto.Repo,
      otp_app: :phoenix_replay,
      adapter: Ecto.Adapters.SQLite3
  end

  setup context do
    db_path = Path.join(System.tmp_dir!(), "phoenix_replay_ecto_#{context.test}.db")

    Application.put_env(:phoenix_replay, Repo,
      database: db_path,
      pool_size: 1,
      stacktrace: true
    )

    start_supervised!(Repo)

    Ecto.Adapters.SQL.query!(Repo, """
    CREATE TABLE phoenix_replay_recordings (
      id TEXT PRIMARY KEY,
      view TEXT NOT NULL,
      connected_at INTEGER NOT NULL,
      event_count INTEGER NOT NULL DEFAULT 0,
      data BLOB NOT NULL,
      inserted_at TEXT,
      updated_at TEXT
    )
    """)

    on_exit(fn -> File.rm(db_path) end)

    %{opts: [repo: Repo], recording: recording("ecto-rec", 1000)}
  end

  test "save and get roundtrip", %{opts: opts, recording: recording} do
    assert :ok = EctoStorage.save(recording, opts)
    assert {:ok, loaded} = EctoStorage.get(recording.id, opts)
    assert loaded.id == recording.id
    assert loaded.view == recording.view
    assert loaded.events == recording.events
  end

  test "list_summaries returns metadata without decoding blobs", %{opts: opts} do
    EctoStorage.save(recording("old", 1000), opts)
    EctoStorage.save(recording("new", 2000), opts)

    assert [new, old] = EctoStorage.list_summaries(opts)
    assert new.id == "new"
    assert old.id == "old"
    assert new.event_count == 2
    assert new.active? == false
  end

  test "delete and clear remove recordings", %{opts: opts} do
    EctoStorage.save(recording("one", 1000), opts)
    EctoStorage.save(recording("two", 2000), opts)

    assert :ok = EctoStorage.delete("one", opts)
    assert EctoStorage.get("one", opts) == :error

    assert :ok = EctoStorage.clear(opts)
    assert EctoStorage.list(opts) == []
  end

  defp recording(id, connected_at) do
    %Recording{
      id: id,
      view: PhoenixReplay.TestLive.Counter,
      url: "/counter",
      params: %{},
      session: %{},
      connected_at: connected_at,
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {100, :event, %{name: "inc", params: %{}}}
      ]
    }
  end
end
