defmodule PhoenixReplay.Store do
  @moduledoc """
  Manages active recordings in ETS and delegates persistence to the
  configured `PhoenixReplay.Storage` backend.

  Active (in-flight) recordings live in ETS for zero-overhead writes.
  When a LiveView process exits, the recording is finalized and persisted.
  """

  use GenServer

  alias PhoenixReplay.Storage

  @active __MODULE__.Active
  @metadata_key -1

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Start recording a session. Called from the LiveView process.
  Monitors the calling process to auto-finalize on exit.
  """
  def start_recording(id, %PhoenixReplay.Recording{} = recording) do
    :ets.insert(@active, {{id, @metadata_key}, recording})
    Process.put(:phoenix_replay_counter, 0)
    GenServer.cast(__MODULE__, {:monitor, self(), id})
  end

  @doc """
  Append an event to an active recording. Called from the LiveView process.
  Pure ETS insert — no GenServer call, no read-modify-write.
  """
  def append_event(id, event) do
    counter = Process.get(:phoenix_replay_counter, 0)
    max = Application.get_env(:phoenix_replay, :max_events, 10_000)

    if counter < max do
      :ets.insert(@active, {{id, counter}, event})
      Process.put(:phoenix_replay_counter, counter + 1)
    end
  end

  @doc """
  Finalize a recording — collect events from ETS, persist via the storage backend.
  """
  def finalize(id) do
    case :ets.lookup(@active, {id, @metadata_key}) do
      [{{^id, @metadata_key}, recording}] ->
        events = collect_events(id)
        recording = %{recording | events: recording.events ++ events}

        if has_user_events?(recording) do
          Storage.backend().save(recording, Storage.storage_opts())
        end

        delete_active(id)

        {:ok, recording}

      [] ->
        :error
    end
  end

  defp has_user_events?(%{events: events}) do
    Enum.any?(events, fn {_, :event, _} -> true; _ -> false end) or
      Enum.count(events, fn {_, :handle_params, _} -> true; _ -> false end) > 1
  end

  @doc """
  Get a finalized recording by ID from the storage backend.
  """
  def get_recording(id) do
    Storage.backend().get(id, Storage.storage_opts())
  end

  @doc """
  Delete all finalized recordings. Useful in tests.
  """
  def clear_all do
    Storage.backend().clear(Storage.storage_opts())
  end

  @doc """
  List all finalized recordings, most recent first.
  """
  def list_recordings do
    Storage.backend().list(Storage.storage_opts())
  end

  @doc """
  Get an active (in-progress) recording snapshot from ETS.
  """
  def get_active(id) do
    case :ets.lookup(@active, {id, @metadata_key}) do
      [{{^id, @metadata_key}, recording}] ->
        events = collect_events(id)
        {:ok, %{recording | events: recording.events ++ events}}

      [] ->
        :error
    end
  end

  defp collect_events(id) do
    match_spec = [{{{id, :"$1"}, :"$2"}, [{:>=, :"$1", 0}], [:"$2"]}]
    :ets.select(@active, match_spec)
  end

  defp delete_active(id) do
    :ets.delete(@active, {id, @metadata_key})
    match_spec = [{{{id, :"$1"}, :_}, [{:>=, :"$1", 0}], [true]}]
    :ets.select_delete(@active, match_spec)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    :ets.new(@active, [:named_table, :public, :ordered_set, write_concurrency: true])
    Storage.backend().init(Storage.storage_opts())
    {:ok, %{monitors: %{}}}
  end

  @impl true
  def handle_cast({:monitor, pid, id}, %{monitors: monitors} = state) do
    ref = Process.monitor(pid)
    {:noreply, %{state | monitors: Map.put(monitors, ref, id)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitors: monitors} = state) do
    case Map.pop(monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {id, monitors} ->
        finalize(id)
        {:noreply, %{state | monitors: monitors}}
    end
  end
end
