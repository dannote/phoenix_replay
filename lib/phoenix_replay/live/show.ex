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
     |> push_event("stop", %{})
     |> push_event("jump", %{index: idx})}
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
    <div class="max-w-5xl mx-auto px-4 py-8">
      <div class="mb-4">
        <.link navigate={@base_path} class="text-sm text-neutral-500 hover:text-neutral-700">← Recordings</.link>
        <h1 class="text-2xl font-bold mt-1">{inspect(@recording.view)}</h1>
        <p class="text-sm text-neutral-500">
          Session <code class="font-mono">{String.slice(@recording.id, 0..11)}</code>
          · {length(@recording.events)} events
          · {format_time(@duration_ms)}
        </p>
      </div>

      <%!-- Player --%>
      <div class="bg-white rounded-lg border border-neutral-200 p-4 mb-4">
        <%!-- Controls row --%>
        <div class="flex items-center gap-2 mb-3">
          <button phx-click="step_back" disabled={@current_index == 0}
            class="px-2 py-1 rounded-md border border-neutral-300 bg-white text-sm hover:bg-neutral-50 disabled:opacity-40 disabled:cursor-default">⏮</button>
          <%= if @playing do %>
            <button phx-click="pause"
              class="px-3 py-1 rounded-md bg-amber-500 text-white text-sm hover:bg-amber-600">⏸</button>
          <% else %>
            <button phx-click="play"
              class="px-3 py-1 rounded-md bg-indigo-600 text-white text-sm hover:bg-indigo-700">▶</button>
          <% end %>
          <button phx-click="step_forward" disabled={@current_index == last_event_index(@recording)}
            class="px-2 py-1 rounded-md border border-neutral-300 bg-white text-sm hover:bg-neutral-50 disabled:opacity-40 disabled:cursor-default">⏭</button>

          <span class="font-mono text-sm text-neutral-600 ml-2">
            {format_time(current_event_ms(@recording, @current_index))} / {format_time(@duration_ms)}
          </span>

          <span class="flex-1"></span>

          <div class="relative group">
            <button class="px-2 py-1 rounded-md border border-neutral-300 bg-white text-sm hover:bg-neutral-50">{@speed}×</button>
            <ul class="hidden group-hover:block absolute bottom-full right-0 bg-white border border-neutral-200 rounded-lg p-1 shadow-lg mb-1">
              <li :for={s <- [1, 2, 5, 10]} phx-click="speed" phx-value-speed={s}
                class="px-3 py-1 text-sm rounded cursor-pointer hover:bg-neutral-100 whitespace-nowrap">{s}×</li>
            </ul>
          </div>
        </div>

        <%!-- Scrubber (Reka UI-style: div-based, no native range input) --%>
        <div
          id="rp-scrubber"
          class="relative flex items-center select-none h-5 touch-none cursor-pointer"
          data-duration={@duration_ms}
          phx-update="ignore"
        >
          <%!-- Track --%>
          <div class="relative flex-1 h-1 bg-neutral-200 rounded-full">
            <%!-- Markers on the track --%>
            <div
              :for={m <- event_markers(@recording.events, @duration_ms)}
              class="absolute top-1/2 -translate-y-1/2 -translate-x-1/2"
              style={"left:#{m.pct}%;"}
              title={event_label(Enum.at(@recording.events, m.index))}
            >
              <div class={[
                "rounded-full",
                if(m.type in [:event, :mount, :handle_params], do: "w-1.5 h-1.5", else: "w-1 h-1")
              ]} style={"background:#{marker_color(m.type)};"} />
            </div>
          </div>
          <%!-- Thumb (positioned by JS) --%>
          <div id="rp-thumb" class="absolute top-1/2 -translate-y-1/2 w-3.5 h-3.5 rounded-full bg-indigo-600 border-2 border-white shadow-sm -translate-x-1/2" style="left:0%;"></div>
        </div>

        <%!-- Hidden forms for JS→server communication --%>
        <form id="rp-tick-bridge" phx-change="tick" phx-update="ignore" class="hidden">
          <input type="hidden" name="index" value="0" />
        </form>
        <form id="rp-scrub-bridge" phx-change="scrub" phx-update="ignore" class="hidden">
          <input type="hidden" name="index" value="0" />
        </form>
        <form id="rp-ended-bridge" phx-change="playback_ended" phx-update="ignore" class="hidden">
          <input type="hidden" name="ended" value="0" />
        </form>
      </div>

      <%!-- Iframe --%>
      <div class="bg-white rounded-lg border border-neutral-200 overflow-hidden mb-4">
        <iframe
          id="replay-frame"
          src={"#{@base_path}/#{@recording.id}/frame"}
          class="w-full h-[600px] border-none block"
        />
      </div>

      <%!-- Events panel --%>
      <div>
        <button phx-click="toggle_events"
          class="px-3 py-1.5 rounded-md border border-neutral-300 bg-white text-sm hover:bg-neutral-50">
          {if @show_events, do: "▼", else: "▶"} Events ({length(@recording.events)})
        </button>

        <div :if={@show_events} class="mt-3 grid grid-cols-1 md:grid-cols-2 gap-3">
          <div class="bg-white rounded-lg border border-neutral-200 p-3">
            <div class="max-h-[500px] overflow-y-auto">
              <button
                :for={{event, i} <- Enum.with_index(@recording.events)}
                phx-click="jump"
                phx-value-index={i}
                class={[
                  "flex items-center gap-2 w-full text-left text-sm px-2 py-1 rounded-md",
                  if(i == @current_index, do: "bg-indigo-600 text-white", else: "hover:bg-neutral-100"),
                  if(i > @current_index, do: "opacity-35")
                ]}
              >
                <span>{event_icon(elem(event, 1))}</span>
                <span class="flex-1 truncate">{event_label(event)}</span>
                <span class={["font-mono text-xs", if(i == @current_index, do: "opacity-70", else: "text-neutral-400")]}>
                  {format_time(elem(event, 0))}
                </span>
              </button>
            </div>
          </div>

          <div class="bg-white rounded-lg border border-neutral-200 p-4">
            <h2 class="text-sm font-semibold mb-2">📦 Assigns</h2>
            <pre class="bg-neutral-100 rounded-md p-3 text-xs overflow-auto whitespace-pre-wrap break-words max-h-80"><%= inspect(Recording.accumulated_assigns(@recording, @current_index), pretty: true, limit: 30) %></pre>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
