defmodule PhoenixReplay.Live.Show do
  use Phoenix.LiveView

  alias PhoenixReplay.{Recording, Store}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    recording =
      case Store.get_recording(id) do
        {:ok, rec} ->
          rec

        :error ->
          case Store.get_active(id) do
            {:ok, rec} -> rec
            :error -> nil
          end
      end

    if recording do
      {:ok,
       socket
       |> assign(:page_title, "Replay: #{inspect(recording.view)}")
       |> assign(:recording, recording)
       |> assign(:base_path, "")
       |> assign(:current_index, 0)
       |> assign(:playing, false)
       |> assign(:speed, 1)
       |> assign(:show_inspector, false)}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    path = url |> URI.parse() |> Map.get(:path, "")
    base_path = path |> String.split("/") |> Enum.drop(-1) |> Enum.join("/")
    {:noreply, assign(socket, :base_path, base_path)}
  end

  @impl true
  def handle_event("step_forward", _, socket) do
    jump(socket, socket.assigns.current_index + 1)
  end

  def handle_event("step_back", _, socket) do
    jump(socket, socket.assigns.current_index - 1)
  end

  def handle_event("jump", %{"index" => index}, socket) do
    jump(socket, String.to_integer(index))
  end

  def handle_event("play", _, socket) do
    send(self(), :tick)
    {:noreply, assign(socket, :playing, true)}
  end

  def handle_event("pause", _, socket) do
    {:noreply, assign(socket, :playing, false)}
  end

  def handle_event("speed", %{"speed" => speed}, socket) do
    {:noreply, assign(socket, :speed, String.to_integer(speed))}
  end

  def handle_event("toggle_inspector", _, socket) do
    {:noreply, assign(socket, :show_inspector, !socket.assigns.show_inspector)}
  end

  defp jump(socket, index) do
    max = length(socket.assigns.recording.events) - 1
    index = max(0, min(index, max))

    broadcast_jump(socket.assigns.recording.id, index)
    {:noreply, assign(socket, :current_index, index)}
  end

  defp broadcast_jump(recording_id, index) do
    Phoenix.PubSub.broadcast(
      PhoenixReplay.PubSub,
      "replay:#{recording_id}",
      {:replay_jump, index}
    )
  end

  @impl true
  def handle_info(:tick, %{assigns: %{playing: false}} = socket), do: {:noreply, socket}

  def handle_info(:tick, socket) do
    %{current_index: index, recording: recording, speed: speed} = socket.assigns
    max = length(recording.events) - 1

    if index < max do
      {current_offset, _, _} = Enum.at(recording.events, index)
      {next_offset, _, _} = Enum.at(recording.events, index + 1)
      delay = max(div(next_offset - current_offset, speed), 10)

      Process.send_after(self(), :tick, delay)
      new_index = index + 1
      broadcast_jump(recording.id, new_index)
      {:noreply, assign(socket, :current_index, new_index)}
    else
      {:noreply, assign(socket, :playing, false)}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp current_event(recording, index) do
    Enum.at(recording.events, index)
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

  defp format_offset(ms) do
    seconds = div(ms, 1000)
    millis = rem(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    if minutes > 0 do
      "#{minutes}:#{String.pad_leading("#{secs}", 2, "0")}.#{String.pad_leading("#{millis}", 3, "0")}"
    else
      "#{secs}.#{String.pad_leading("#{millis}", 3, "0")}s"
    end
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
        </p>
      </div>

      <%!-- Playback controls --%>
      <div class="rp-card" style="margin-bottom:1rem;">
        <div class="rp-controls">
          <button phx-click="step_back" class="rp-btn" disabled={@current_index == 0}>⏮</button>
          <button :if={!@playing} phx-click="play" class="rp-btn rp-btn-primary">▶ Play</button>
          <button :if={@playing} phx-click="pause" class="rp-btn rp-btn-warning">⏸ Pause</button>
          <button phx-click="step_forward" class="rp-btn" disabled={@current_index == length(@recording.events) - 1}>⏭</button>

          <input
            type="range"
            min="0"
            max={length(@recording.events) - 1}
            value={@current_index}
            phx-change="jump"
            name="index"
            class="rp-range"
          />

          <span class="rp-mono" style="font-size:0.875rem; min-width:60px; text-align:right;">
            {@current_index + 1}/{length(@recording.events)}
          </span>

          <div class="rp-speed-menu">
            <button class="rp-btn">{@speed}x</button>
            <ul>
              <li :for={s <- [1, 2, 5, 10]} phx-click="speed" phx-value-speed={s}>{s}x</li>
            </ul>
          </div>
        </div>
      </div>

      <div style="display:grid; grid-template-columns:1fr 280px; gap:1rem;">
        <%!-- Visual replay iframe --%>
        <div class="rp-card" style="overflow:hidden;">
          <iframe
            id="replay-frame"
            src={"#{@base_path}/#{@recording.id}/frame"}
            style="width:100%; height:600px; border:none; display:block;"
          />
        </div>

        <%!-- Event timeline sidebar --%>
        <div class="rp-card">
          <div class="rp-card-body" style="padding:0.75rem;">
            <h2 style="font-size:0.875rem; font-weight:600; margin:0 0 0.5rem; padding:0 0.5rem;">Timeline</h2>
            <div class="rp-timeline">
              <button
                :for={{event, i} <- Enum.with_index(@recording.events)}
                phx-click="jump"
                phx-value-index={i}
                class={"rp-timeline-item #{if i == @current_index, do: "active"} #{if i > @current_index, do: "future"}"}
                style="font-size:0.8125rem; padding:0.375rem 0.5rem;"
              >
                <span>{event_icon(elem(event, 1))}</span>
                <span style="flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">
                  {event_label(event)}
                </span>
                <span class="rp-mono" style={"font-size:0.6875rem; #{if i == @current_index, do: "opacity:0.7;", else: "color:#a3a3a3;"}"}>
                  {format_offset(elem(event, 0))}
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Collapsible inspector --%>
      <div style="margin-top:1rem;">
        <button phx-click="toggle_inspector" class="rp-btn" style="font-size:0.8125rem;">
          {if @show_inspector, do: "▼", else: "▶"} Inspector
        </button>

        <div :if={@show_inspector} class="rp-grid" style="margin-top:0.75rem;">
          <div class="rp-card">
            <div class="rp-card-body">
              <h2 style="font-size:0.875rem; font-weight:600; margin:0 0 0.5rem;">
                {event_icon(elem(current_event(@recording, @current_index), 1))} Current Event
              </h2>
              <pre class="rp-pre"><%= inspect(current_event(@recording, @current_index), pretty: true, limit: 50) %></pre>
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
