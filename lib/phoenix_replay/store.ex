defmodule PhoenixReplay.Store do
  @moduledoc """
  Manages active recordings in ETS and delegates persistence to the
  configured `PhoenixReplay.Storage` backend.

  Events are appended via pure ETS writes — no GenServer call on the hot path.
  When a LiveView process exits, the recording is finalized and persisted.
  """

  use GenServer

  require Logger

  alias PhoenixReplay.{Persistence, Recordings, Storage}

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
      case :ets.whereis(@active) do
        :undefined ->
          Logger.warning("PhoenixReplay: active recording table is unavailable")
          :error

        _table ->
          :ets.insert(@active, {{id, counter}, event})
          Process.put(:phoenix_replay_counter, counter + 1)
      end
    end
  end

  @doc """
  Finalize a recording — collect events from ETS, persist via the storage backend.

  Recordings with no user events (no `handle_event`, at most one `handle_params`)
  are silently discarded to avoid storing empty page views.
  """
  def finalize(id) do
    case finalized_recording(id) do
      {:ok, recording} -> persist_finalized(recording, sync?: true)
      :error -> :error
    end
  end

  defp finalize_async(id) do
    case finalized_recording(id) do
      {:ok, recording} -> persist_finalized(recording, sync?: false)
      :error -> :error
    end
  end

  defp finalized_recording(id) do
    case :ets.lookup(@active, {id, @metadata_key}) do
      [{{^id, @metadata_key}, recording}] ->
        events = collect_events(id)
        {:ok, %{recording | events: recording.events ++ events}}

      [] ->
        :error
    end
  end

  defp persist_finalized(recording, sync?: sync?) do
    if has_user_events?(recording) do
      if sync? do
        case Persistence.save(recording) do
          :ok ->
            delete_active(recording.id)
            {:ok, recording}

          {:error, reason} ->
            Logger.error(
              "PhoenixReplay: failed to persist recording #{recording.id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      else
        Persistence.save_async(recording)
        {:ok, recording}
      end
    else
      delete_active(recording.id)
      {:ok, recording}
    end
  end

  defp has_user_events?(%{events: events}) do
    Enum.reduce_while(events, 0, fn
      {_, :event, _}, _handle_params_count ->
        {:halt, true}

      {_, :handle_params, _}, handle_params_count ->
        handle_params_count = handle_params_count + 1

        if handle_params_count > 1 do
          {:halt, true}
        else
          {:cont, handle_params_count}
        end

      _, handle_params_count ->
        {:cont, handle_params_count}
    end) == true
  end

  @doc """
  Get a finalized recording by ID from the storage backend.
  """
  def get_recording(id) do
    case Persistence.storage_call(:get, [id, Storage.storage_opts()], :error) do
      {:ok, recording} -> authorize_recording(recording)
      :error -> :error
    end
  end

  @doc """
  Delete all finalized recordings. Useful in tests.
  """
  def clear_all do
    Persistence.storage_call(:clear, [Storage.storage_opts()], :ok)
  end

  def delete_recording(id) do
    Persistence.storage_call(:delete, [id, Storage.storage_opts()], :ok)
  end

  @doc """
  List all finalized recordings, most recent first.
  """
  def list_recordings do
    :list
    |> Persistence.storage_call([Storage.storage_opts()], [])
    |> Enum.flat_map(fn recording ->
      case authorize_recording(recording) do
        {:ok, recording} -> [recording]
        :error -> []
      end
    end)
  end

  @doc """
  List all finalized recording summaries, most recent first.
  """
  def list_recording_summaries do
    summaries =
      if function_exported?(Storage.backend(), :list_summaries, 1) do
        Persistence.storage_call(:list_summaries, [Storage.storage_opts()], [])
      else
        Enum.map(list_recordings(), &Recordings.summary/1)
      end

    Enum.filter(summaries, &authorized_summary?/1)
  end

  @doc """
  Get an active (in-progress) recording snapshot from ETS.
  """
  def get_active(id) do
    case :ets.lookup(@active, {id, @metadata_key}) do
      [{{^id, @metadata_key}, recording}] ->
        events = collect_events(id)
        recording = %{recording | events: recording.events ++ events}
        authorize_recording(recording)

      [] ->
        :error
    end
  end

  @doc """
  List active recordings that have user interaction, most recent first.

  Uses the monitor registry to enumerate active recording IDs —
  no `:sys.get_state` calls or private LiveView APIs.
  """
  def list_active do
    GenServer.call(__MODULE__, :list_active)
  end

  def list_active_summaries do
    GenServer.call(__MODULE__, :list_active_summaries)
  end

  def persisted(id) do
    GenServer.cast(__MODULE__, {:persisted, id})
  end

  def cleanup do
    summaries = list_recording_summaries()
    now = System.system_time(:millisecond)

    summaries
    |> expired_summaries(now)
    |> Enum.each(&delete_recording(&1.id))

    :ok
  end

  def cleanup_async do
    GenServer.cast(__MODULE__, :cleanup)
  end

  def authorize_recording(recording) do
    authorize = Application.get_env(:phoenix_replay, :authorize, fn _recording -> true end)

    if authorize.(recording), do: {:ok, recording}, else: :error
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

  defp authorized_summary?(summary) do
    match?({:ok, _}, summary |> summary_recording() |> authorize_recording())
  end

  defp expired_summaries(summaries, now) do
    by_age =
      case Application.get_env(:phoenix_replay, :max_recording_age_ms) do
        age when is_integer(age) and age > 0 ->
          Enum.filter(summaries, &(now - &1.connected_at > age))

        _ ->
          []
      end

    by_count =
      case Application.get_env(:phoenix_replay, :max_recordings) do
        max when is_integer(max) and max >= 0 ->
          summaries
          |> Enum.sort_by(& &1.connected_at, :desc)
          |> Enum.drop(max)

        _ ->
          []
      end

    (by_age ++ by_count)
    |> Enum.uniq_by(& &1.id)
    |> Enum.reject(& &1.active?)
  end

  defp summary_recording(summary) do
    %PhoenixReplay.Recording{
      id: summary.id,
      view: summary.view,
      url: summary.url,
      params: %{},
      session: %{},
      connected_at: summary.connected_at,
      events: []
    }
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    :ets.new(@active, [:named_table, :public, :ordered_set, write_concurrency: true])

    case Persistence.init_storage() do
      :ok ->
        Logger.debug("PhoenixReplay: storage initialized")

      {:error, reason} ->
        Logger.error("PhoenixReplay: storage initialization failed: #{inspect(reason)}")
    end

    if interval = Application.get_env(:phoenix_replay, :cleanup_interval_ms) do
      :timer.send_interval(interval, :cleanup)
    end

    {:ok, %{monitors: %{}}}
  end

  @impl true
  def handle_call(:list_active, _from, %{monitors: monitors} = state) do
    recordings =
      monitors
      |> Map.values()
      |> Enum.flat_map(fn id ->
        case get_active(id) do
          {:ok, rec} -> if has_user_events?(rec), do: [rec], else: []
          :error -> []
        end
      end)
      |> Enum.sort_by(& &1.connected_at, :desc)

    {:reply, recordings, state}
  end

  @impl true
  def handle_call(:list_active_summaries, _from, %{monitors: monitors} = state) do
    summaries =
      monitors
      |> Map.values()
      |> Enum.flat_map(fn id ->
        case get_active(id) do
          {:ok, rec} -> if has_user_events?(rec), do: [Recordings.active_summary(rec)], else: []
          :error -> []
        end
      end)
      |> Enum.sort_by(& &1.connected_at, :desc)

    {:reply, summaries, state}
  end

  @impl true
  def handle_cast({:monitor, pid, id}, %{monitors: monitors} = state) do
    ref = Process.monitor(pid)
    {:noreply, %{state | monitors: Map.put(monitors, ref, id)}}
  end

  @impl true
  def handle_cast({:persisted, id}, state) do
    delete_active(id)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:cleanup, state) do
    cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup()
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitors: monitors} = state) do
    case Map.pop(monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {id, monitors} ->
        case finalize_async(id) do
          {:ok, _recording} ->
            :ok

          {:error, reason} ->
            Logger.error("PhoenixReplay: recording #{id} was not finalized: #{inspect(reason)}")

          :error ->
            :ok
        end

        {:noreply, %{state | monitors: monitors}}
    end
  end
end
