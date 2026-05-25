defmodule PhoenixReplay.Persistence do
  @moduledoc false

  use GenServer

  require Logger

  alias PhoenixReplay.Storage

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def save(recording) do
    GenServer.call(__MODULE__, {:save, recording}, :infinity)
  end

  def save_async(recording) do
    GenServer.cast(__MODULE__, {:save, recording})
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:save, recording}, _from, state) do
    {:reply, persist(recording), state}
  end

  @impl true
  def handle_cast({:save, recording}, state) do
    case persist(recording) do
      :ok ->
        PhoenixReplay.Store.persisted(recording.id)

      {:error, reason} ->
        Logger.error(
          "PhoenixReplay: failed to persist recording #{recording.id}: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  end

  def init_storage do
    storage_call(:init, [Storage.storage_opts()], {:error, :storage_unavailable})
  end

  def storage_call(function, args, fallback) do
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

  defp persist(recording) do
    storage_call(:save, [recording, Storage.storage_opts()], {:error, :storage_unavailable})
  end
end
