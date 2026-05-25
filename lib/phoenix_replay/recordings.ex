defmodule PhoenixReplay.Recordings do
  @moduledoc false

  alias PhoenixReplay.{Recording, Store}

  def fetch(id) do
    case Store.get_recording(id) do
      {:ok, recording} -> Store.authorize_recording(recording)
      :error -> fetch_active(id)
    end
  end

  def fetch!(id) do
    case fetch(id) do
      {:ok, recording} -> recording
      :error -> raise "Recording not found: #{id}"
    end
  end

  def list_summaries do
    Store.list_active_summaries() ++ Store.list_recording_summaries()
  end

  def event_offsets(%Recording{events: events}) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {{ms, _, _}, i} -> %{ms: ms, index: i} end)
  end

  def total_duration(%Recording{events: []}), do: 0

  def total_duration(%Recording{events: events}) do
    {ms, _, _} = List.last(events)
    ms
  end

  def summary(%Recording{} = recording) do
    %{
      id: recording.id,
      view: recording.view,
      url: recording.url,
      connected_at: recording.connected_at,
      event_count: length(recording.events),
      duration_ms: total_duration(recording),
      active?: false
    }
  end

  def active_summary(%Recording{} = recording) do
    %{summary(recording) | active?: true}
  end

  defp fetch_active(id) do
    case Store.get_active(id) do
      {:ok, recording} -> Store.authorize_recording(recording)
      :error -> :error
    end
  end
end
