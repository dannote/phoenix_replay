defmodule PhoenixReplay.Live.Show do
  use Phoenix.LiveView

  alias PhoenixReplay.{Recording, Store}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    recording =
      case Store.get_recording(id) do
        {:ok, rec} -> rec
        :error ->
          case Store.get_active(id) do
            {:ok, rec} -> rec
            :error -> nil
          end
      end

    if recording do
      duration_ms = total_duration(recording)

      event_offsets =
        recording.events
        |> Enum.with_index()
        |> Enum.map(fn {{ms, _, _}, i} -> %{ms: ms, index: i} end)

      {:ok,
       socket
       |> assign(:page_title, "Replay: #{inspect(recording.view)}")
       |> assign(:recording, recording)
       |> assign(:base_path, "")
       |> assign(:current_index, 0)
       |> assign(:duration_ms, duration_ms)
       |> assign(:event_offsets, event_offsets)
       |> assign(:speed, 1)
       |> assign(:playing, false)
       |> assign(:show_events, false)}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    path = url |> URI.parse() |> Map.get(:path, "")
    base_path = path |> String.split("/") |> Enum.drop(-1) |> Enum.join("/")

    {:noreply,
     socket
     |> assign(:base_path, base_path)
     |> push_event("init", %{
       events: socket.assigns.event_offsets,
       speed: socket.assigns.speed
     })}
  end

  @impl true
  def handle_event("step_forward", _, socket) do
    jump_to(socket, socket.assigns.current_index + 1)
  end

  def handle_event("step_back", _, socket) do
    jump_to(socket, socket.assigns.current_index - 1)
  end

  def handle_event("jump", %{"index" => index}, socket) do
    jump_to(socket, String.to_integer(index))
  end

  def handle_event("tick", %{"index" => index}, socket) do
    idx = clamp_index(socket, String.to_integer(index))
    broadcast_jump(socket.assigns.recording.id, idx)
    {:noreply, assign(socket, :current_index, idx)}
  end

  def handle_event("scrub", %{"index" => index}, socket) do
    idx = clamp_index(socket, String.to_integer(index))
    broadcast_jump(socket.assigns.recording.id, idx)

    {:noreply,
     socket
     |> assign(:current_index, idx)
     |> assign(:playing, false)}
  end

  def handle_event("play", _, socket) do
    {:noreply,
     socket
     |> assign(:playing, true)
     |> push_event("play", %{speed: socket.assigns.speed})}
  end

  def handle_event("pause", _, socket) do
    {:noreply,
     socket
     |> assign(:playing, false)
     |> push_event("stop", %{})}
  end

  def handle_event("playback_ended", _, socket) do
    {:noreply, assign(socket, :playing, false)}
  end

  def handle_event("speed", %{"speed" => speed}, socket) do
    speed = String.to_integer(speed)

    {:noreply,
     socket
     |> assign(:speed, speed)
     |> push_event("speed", %{speed: speed})}
  end

  def handle_event("toggle_events", _, socket) do
    {:noreply, assign(socket, :show_events, !socket.assigns.show_events)}
  end

  defp jump_to(socket, index) do
    idx = clamp_index(socket, index)

    broadcast_jump(socket.assigns.recording.id, idx)

    {:noreply,
     socket
     |> assign(:current_index, idx)
     |> assign(:playing, false)
     |> push_event("stop", %{})}
  end

  defp clamp_index(socket, index) do
    max = length(socket.assigns.recording.events) - 1
    max(0, min(index, max))
  end

  defp broadcast_jump(recording_id, index) do
    Phoenix.PubSub.broadcast(
      PhoenixReplay.PubSub,
      "replay:#{recording_id}",
      {:replay_jump, index}
    )
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  defp current_event_ms(recording, index) do
    case Enum.at(recording.events, index) do
      {ms, _, _} -> ms
      _ -> 0
    end
  end

  defp total_duration(%{events: []}), do: 0

  defp total_duration(%{events: events}) do
    {ms, _, _} = List.last(events)
    ms
  end

  defp last_event_index(%{events: []}), do: 0
  defp last_event_index(%{events: events}), do: length(events) - 1

  defp event_markers(_events, duration_ms) when duration_ms <= 0, do: []

  defp event_markers(events, duration_ms) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {{ms, type, _}, i} ->
      %{index: i, type: type, pct: ms / duration_ms * 100}
    end)
  end

  defp event_icon(:mount), do: "🚀"
  defp event_icon(:event), do: "⚡"
  defp event_icon(:handle_params), do: "🔗"
  defp event_icon(:info), do: "📨"
  defp event_icon(:assigns), do: "📝"
  defp event_icon(_), do: "·"

  defp event_label({_, :mount, _}), do: "mount"
  defp event_label({_, :event, %{name: name}}), do: name
  defp event_label({_, :handle_params, %{url: url}}), do: "navigate → #{url}"
  defp event_label({_, :handle_params, _}), do: "handle_params"
  defp event_label({_, :info, _}), do: "handle_info"
  defp event_label({_, :assigns, _}), do: "assigns changed"
  defp event_label({_, type, _}), do: to_string(type)

  defp marker_color(:mount), do: "#4f46e5"
  defp marker_color(:event), do: "#f59e0b"
  defp marker_color(:handle_params), do: "#0ea5e9"
  defp marker_color(:assigns), do: "#a3a3a3"
  defp marker_color(_), do: "#737373"

  defp format_time(ms) do
    total_sec = div(ms, 1000)
    m = div(total_sec, 60)
    s = rem(total_sec, 60)
    "#{m}:#{String.pad_leading("#{s}", 2, "0")}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rp-container" style="max-width:1200px;">
      <div style="margin-bottom:1rem;">
        <.link navigate={@base_path} style="font-size:0.875rem;" class="rp-muted">← Recordings</.link>
        <h1 style="font-size:1.5rem; font-weight:700; margin:0.25rem 0;">{inspect(@recording.view)}</h1>
        <p class="rp-muted" style="font-size:0.875rem; margin:0;">
          Session <code class="rp-mono">{String.slice(@recording.id, 0..11)}</code>
          · {length(@recording.events)} events
          · {format_time(@duration_ms)}
        </p>
      </div>

      <%!-- Player --%>
      <div class="rp-card" style="margin-bottom:1rem;">
        <div style="padding:0.75rem 1.25rem;">
          <%!-- Controls row --%>
          <div style="display:flex; align-items:center; gap:0.5rem; margin-bottom:0.75rem;">
            <button phx-click="step_back" class="rp-btn" disabled={@current_index == 0} style="padding:0.25rem 0.5rem;">⏮</button>
            <%= if @playing do %>
              <button phx-click="pause" class="rp-btn rp-btn-warning" style="padding:0.25rem 0.75rem;">⏸</button>
            <% else %>
              <button phx-click="play" class="rp-btn rp-btn-primary" style="padding:0.25rem 0.75rem;">▶</button>
            <% end %>
            <button phx-click="step_forward" class="rp-btn" disabled={@current_index == last_event_index(@recording)} style="padding:0.25rem 0.5rem;">⏭</button>

            <span class="rp-mono" style="font-size:0.8125rem; margin-left:0.5rem; color:#525252;">
              {format_time(current_event_ms(@recording, @current_index))} / {format_time(@duration_ms)}
            </span>

            <span style="flex:1;"></span>

            <div class="rp-speed-menu">
              <button class="rp-btn" style="padding:0.25rem 0.5rem; font-size:0.8125rem;">{@speed}×</button>
              <ul>
                <li :for={s <- [1, 2, 5, 10]} phx-click="speed" phx-value-speed={s}>{s}×</li>
              </ul>
            </div>
          </div>

          <%!-- Scrubber: value = event index, max = last event index --%>
          <div class="rp-scrub-wrap">
            <div
              :for={m <- event_markers(@recording.events, @duration_ms)}
              class="rp-scrub-marker"
              style={"left:#{m.pct}%;"}
              title={event_label(Enum.at(@recording.events, m.index))}
            >
              <div style={"width:#{if m.type in [:event, :mount, :handle_params], do: 6, else: 3}px; height:#{if m.type in [:event, :mount, :handle_params], do: 6, else: 3}px; border-radius:50%; background:#{marker_color(m.type)};"}></div>
            </div>
            <input
              id="rp-scrubber"
              type="range"
              min="0"
              max={last_event_index(@recording)}
              value={@current_index}
              step="1"
              class="rp-scrub-range"
              phx-update="ignore"
            />
          </div>
          <%!-- Hidden forms for JS→server communication --%>
          <form id="rp-tick-bridge" phx-change="tick" phx-update="ignore" style="display:none;">
            <input type="hidden" name="index" value="0" />
          </form>
          <form id="rp-scrub-bridge" phx-change="scrub" phx-update="ignore" style="display:none;">
            <input type="hidden" name="index" value="0" />
          </form>
          <form id="rp-ended-bridge" phx-change="playback_ended" phx-update="ignore" style="display:none;">
            <input type="hidden" name="ended" value="0" />
          </form>
        </div>
      </div>

      <%!-- Iframe --%>
      <div class="rp-card" style="overflow:hidden; margin-bottom:1rem;">
        <iframe
          id="replay-frame"
          src={"#{@base_path}/#{@recording.id}/frame"}
          style="width:100%; height:600px; border:none; display:block;"
        />
      </div>

      <%!-- Events panel --%>
      <div>
        <button phx-click="toggle_events" class="rp-btn" style="font-size:0.8125rem;">
          {if @show_events, do: "▼", else: "▶"} Events ({length(@recording.events)})
        </button>

        <div :if={@show_events} style="margin-top:0.75rem; display:grid; grid-template-columns:1fr 1fr; gap:0.75rem;">
          <div class="rp-card">
            <div class="rp-card-body" style="padding:0.75rem;">
              <div class="rp-timeline">
                <button
                  :for={{event, i} <- Enum.with_index(@recording.events)}
                  phx-click="jump"
                  phx-value-index={i}
                  class={"rp-timeline-item #{if i == @current_index, do: "active"} #{if i > @current_index, do: "future"}"}
                  style="font-size:0.8125rem; padding:0.25rem 0.5rem;"
                >
                  <span>{event_icon(elem(event, 1))}</span>
                  <span style="flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">
                    {event_label(event)}
                  </span>
                  <span class="rp-mono" style={"font-size:0.6875rem; #{if i == @current_index, do: "opacity:0.7;", else: "color:#a3a3a3;"}"}>
                    {format_time(elem(event, 0))}
                  </span>
                </button>
              </div>
            </div>
          </div>

          <div class="rp-card">
            <div class="rp-card-body">
              <h2 style="font-size:0.875rem; font-weight:600; margin:0 0 0.5rem;">📦 Assigns</h2>
              <pre class="rp-pre"><%= inspect(Recording.accumulated_assigns(@recording, @current_index), pretty: true, limit: 30) %></pre>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
