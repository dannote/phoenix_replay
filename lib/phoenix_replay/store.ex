defmodule PhoenixReplay.Store do
  @moduledoc """
  In-memory store for recordings backed by ETS.

  Uses two ETS tables:
  - **active** (`ordered_set`) — keyed by `{session_id, counter}` for O(1) event appends.
    The recording metadata is stored at `{session_id, -1}`.
  - **recordings** — finalized recordings, keyed by session ID.

  Each LiveView process writes events directly to ETS — no message passing,
  no backpressure.
  """

  use GenServer

  @active __MODULE__.Active
  @recordings __MODULE__.Recordings
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
  Finalize a recording — collect metadata + events, move to recordings table.
  """
  def finalize(id) do
    case :ets.lookup(@active, {id, @metadata_key}) do
      [{{^id, @metadata_key}, recording}] ->
        events = collect_events(id)
        recording = %{recording | events: recording.events ++ events}

        :ets.insert(@recordings, {id, recording})
        delete_active(id)

        {:ok, recording}

      [] ->
        :error
    end
  end

  @doc """
  Get a finalized recording by ID.
  """
  def get_recording(id) do
    case :ets.lookup(@recordings, id) do
      [{^id, recording}] -> {:ok, recording}
      [] -> :error
    end
  end

  @doc """
  List all finalized recordings, most recent first.
  """
  def list_recordings do
    :ets.tab2list(@recordings)
    |> Enum.map(fn {_id, rec} -> rec end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @doc """
  Get an active (in-progress) recording snapshot.
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
    # ETS ordered_set: keys are sorted, so {id, 0} < {id, 1} < ...
    # We select all keys matching {id, counter} where counter >= 0
    match_spec = [{{{id, :"$1"}, :"$2"}, [{:>=, :"$1", 0}], [:"$2"]}]
    :ets.select(@active, match_spec)
  end

  defp delete_active(id) do
    # Delete metadata key
    :ets.delete(@active, {id, @metadata_key})

    # Delete all event keys — we know the counter range
    match_spec = [{{{id, :"$1"}, :_}, [{:>=, :"$1", 0}], [true]}]
    :ets.select_delete(@active, match_spec)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    :ets.new(@active, [:named_table, :public, :ordered_set, write_concurrency: true])
    :ets.new(@recordings, [:named_table, :public, :set, read_concurrency: true])
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
