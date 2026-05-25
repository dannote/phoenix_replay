defmodule PhoenixReplay.PersistenceTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.{Persistence, Recording, Store}

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
    original_storage = Application.get_env(:phoenix_replay, :storage)

    on_exit(fn ->
      if original_storage do
        Application.put_env(:phoenix_replay, :storage, original_storage)
      else
        Application.delete_env(:phoenix_replay, :storage)
      end
    end)

    %{recording: recording()}
  end

  test "save delegates to configured storage", %{recording: recording} do
    assert :ok = Persistence.save(recording)
    assert {:ok, loaded} = Store.get_recording(recording.id)
    assert loaded.id == recording.id
  end

  test "save returns storage errors", %{recording: recording} do
    Application.put_env(:phoenix_replay, :storage, FailingStorage)

    assert {:error, :failed} = Persistence.save(recording)
  end

  defp recording do
    %Recording{
      id: "persistence-test",
      view: PhoenixReplay.TestLive.Counter,
      url: "/counter",
      params: %{},
      session: %{},
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {100, :event, %{name: "inc", params: %{}}}
      ]
    }
  end
end
