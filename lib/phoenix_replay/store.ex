defmodule PhoenixReplay.Store do
  @moduledoc """
  Manages active recordings in ETS and delegates persistence to the
  configured `PhoenixReplay.Storage` backend.

  Events are appended via pure ETS writes — no GenServer call on the hot path.
  When a LiveView process exits, the recording is finalized and persisted.
  """

  use GenServer

  require Logger

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
    case :ets.lookup(@active, {id, @metadata_key}) do
      [{{^id, @metadata_key}, recording}] ->
        events = collect_events(id)
        recording = %{recording | events: recording.events ++ events}

        if has_user_events?(recording) do
          case save_recording(recording) do
            :ok ->
              delete_active(id)
              {:ok, recording}

            {:error, reason} ->
              Logger.error("PhoenixReplay: failed to persist recording #{id}: #{inspect(reason)}")
              {:error, reason}
          end
        else
          delete_active(id)
          {:ok, recording}
        end

      [] ->
        :error
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
    safe_storage_call(:get, [id, Storage.storage_opts()], :error)
  end

  @doc """
  Delete all finalized recordings. Useful in tests.
  """
  def clear_all do
    safe_storage_call(:clear, [Storage.storage_opts()], :ok)
  end

  @doc """
  List all finalized recordings, most recent first.
  """
  def list_recordings do
    safe_storage_call(:list, [Storage.storage_opts()], [])
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

  @doc """
  List active recordings that have user interaction, most recent first.

  Uses the monitor registry to enumerate active recording IDs —
  no `:sys.get_state` calls or private LiveView APIs.
  """
  def list_active do
    GenServer.call(__MODULE__, :list_active)
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

  defp save_recording(recording) do
    safe_storage_call(:save, [recording, Storage.storage_opts()], {:error, :storage_unavailable})
  end

  defp safe_storage_call(function, args, fallback) do
    apply(Storage.backend(), function, args)
  rescue
    e in [
      ArgumentError,
      ErlangError,
      File.Error,
      FunctionClauseError,
      KeyError,
      MatchError,
      RuntimeError,
      UndefinedFunctionError
    ] ->
      Logger.error(
        "PhoenixReplay: storage #{function} failed: #{Exception.format(:error, e, __STACKTRACE__)}"
      )

      fallback
  catch
    kind, reason ->
      Logger.error("PhoenixReplay: storage #{function} failed: #{inspect({kind, reason})}")
      fallback
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    :ets.new(@active, [:named_table, :public, :ordered_set, write_concurrency: true])

    case safe_storage_call(:init, [Storage.storage_opts()], {:error, :storage_unavailable}) do
      :ok ->
        Logger.debug("PhoenixReplay: storage initialized")

      {:error, reason} ->
        Logger.error("PhoenixReplay: storage initialization failed: #{inspect(reason)}")
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
        case finalize(id) do
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
