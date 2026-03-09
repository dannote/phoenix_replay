defmodule PhoenixReplay.Live.Index do
  use Phoenix.LiveView

  alias PhoenixReplay.Store

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(2000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "PhoenixReplay")
     |> assign(:base_path, "")
     |> assign(:recordings, list_all())}
  end

  @impl true
  def handle_params(_params, url, socket) do
    base_path = url |> URI.parse() |> Map.get(:path, "") |> String.trim_trailing("/")
    {:noreply, assign(socket, :base_path, base_path)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :recordings, list_all())}
  end

  defp list_all do
    active = active_recordings()
    finished = Store.list_recordings()
    active ++ finished
  end

  defp active_recordings do
    self_pid = self()

    Phoenix.LiveView.Debug.list_liveviews()
    |> Enum.flat_map(fn %{pid: pid} ->
      if pid == self_pid do
        []
      else
        try do
          case :sys.get_state(pid, 100) do
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
        catch
          :exit, _ -> []
        end
      end
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  defp format_time(ms) when is_integer(ms) do
    DateTime.from_unix!(ms, :millisecond) |> Calendar.strftime("%H:%M:%S")
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

    if minutes > 0, do: "#{minutes}m #{secs}s", else: "#{secs}s"
  end

  defp active?(recording) do
    case Store.get_active(recording.id) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rp-container">
      <div class="rp-header">
        <h1>📹 PhoenixReplay</h1>
        <span class="rp-muted" style="font-size:0.875rem">
          {length(@recordings)} recording{if length(@recordings) != 1, do: "s"}
        </span>
      </div>

      <div :if={@recordings == []} class="rp-empty">
        <div class="rp-empty-icon">📹</div>
        <p>No recordings yet.</p>
        <p class="rp-muted" style="font-size:0.875rem">
          Add <code>on_mount: [PhoenixReplay.Recorder]</code> to a live_session and start using your app.
        </p>
      </div>

      <.link
        :for={rec <- @recordings}
        navigate={"#{@base_path}/#{rec.id}"}
        class="rp-card"
        style="display:block; color:inherit; text-decoration:none;"
      >
        <div class="rp-card-body" style="display:flex; align-items:center; justify-content:space-between;">
          <div>
            <div style="font-weight:500; display:flex; align-items:center; gap:0.5rem;">
              {inspect(rec.view)}
              <span :if={active?(rec)} class="rp-badge rp-badge-live">
                <span class="rp-dot-live" /> LIVE
              </span>
            </div>
            <div class="rp-muted" style="font-size:0.875rem; margin-top:0.25rem;">
              Started at {format_time(rec.connected_at)}
              · {length(rec.events)} events
              · {format_duration(duration_ms(rec))}
            </div>
          </div>
          <div class="rp-mono rp-muted" style="font-size:0.8125rem;">
            {String.slice(rec.id, 0..7)}
          </div>
        </div>
      </.link>
    </div>
    """
  end
end
