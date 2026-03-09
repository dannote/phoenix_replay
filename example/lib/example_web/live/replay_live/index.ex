defmodule ExampleWeb.ReplayLive.Index do
  use ExampleWeb, :live_view

  alias PhoenixReplay.Store

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(2000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "Session Recordings")
     |> assign(:recordings, list_all())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :recordings, list_all())}
  end

  defp list_all do
    recordings = Store.list_recordings()
    active = active_recordings()
    active ++ recordings
  end

  defp active_recordings do
    Phoenix.LiveView.Debug.list_liveviews()
    |> Enum.flat_map(fn %{pid: pid} ->
      try do
        case :sys.get_state(pid) do
          %{socket: %{assigns: %{_replay_id: id}}} ->
            case Store.get_active(id) do
              {:ok, rec} -> [rec]
              :error -> []
            end

          _ ->
            []
        end
      rescue
        _ -> []
      end
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  defp format_time(ms) when is_integer(ms) do
    DateTime.from_unix!(ms, :millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp event_count(recording) do
    length(recording.events)
  end

  defp duration_ms(recording) do
    case List.last(recording.events) do
      {offset, _, _} -> offset
      nil -> 0
    end
  end

  defp format_duration(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    cond do
      minutes > 0 -> "#{minutes}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  defp active?(recording) do
    case Store.get_active(recording.id) do
      {:ok, _} -> true
      :error -> false
    end
  end
end
