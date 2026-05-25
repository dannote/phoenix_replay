defmodule PhoenixReplay.StorageTest do
  use ExUnit.Case, async: false

  test "backend returns configured storage module" do
    original_storage = Application.get_env(:phoenix_replay, :storage)

    on_exit(fn ->
      if original_storage do
        Application.put_env(:phoenix_replay, :storage, original_storage)
      else
        Application.delete_env(:phoenix_replay, :storage)
      end
    end)

    Application.put_env(:phoenix_replay, :storage, PhoenixReplay.Storage.File)

    assert PhoenixReplay.Storage.backend() == PhoenixReplay.Storage.File
  end

  test "storage_opts returns configured options" do
    original_opts = Application.get_env(:phoenix_replay, :storage_opts)

    on_exit(fn ->
      if original_opts do
        Application.put_env(:phoenix_replay, :storage_opts, original_opts)
      else
        Application.delete_env(:phoenix_replay, :storage_opts)
      end
    end)

    Application.put_env(:phoenix_replay, :storage_opts, path: "tmp/replay", format: :json)

    assert PhoenixReplay.Storage.storage_opts() == [path: "tmp/replay", format: :json]
  end
end
