defmodule PhoenixReplay.Live.Show do
  @moduledoc false
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
       |> assign(:playing, false)}
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

  defp event_label({_, :event, %{name: name, params: params}}) do
    summary = params_summary(params)
    if summary, do: "#{name}: #{summary}", else: name
  end

  defp event_label({_, :event, %{name: name}}), do: name
  defp event_label({_, :handle_params, %{url: url}}), do: "navigate → #{url}"
  defp event_label({_, :handle_params, _}), do: "handle_params"
  defp event_label({_, :info, _}), do: "handle_info"
  defp event_label({_, :assigns, _}), do: "assigns changed"
  defp event_label({_, type, _}), do: to_string(type)

  defp params_summary(%{"_target" => [field | _]} = params) do
    value = get_in(params, [field]) || nested_value(params, field)

    case value do
      v when is_binary(v) and v != "" -> "#{field}=#{String.slice(v, 0..39)}"
      _ -> field
    end
  end

  defp params_summary(params) when is_map(params) do
    params
    |> Enum.reject(fn {k, _} -> String.starts_with?(k, "_") end)
    |> Enum.flat_map(fn
      {_key, nested} when is_map(nested) ->
        nested
        |> Enum.filter(fn {_, v} -> is_binary(v) and v != "" end)
        |> Enum.map(fn {k, v} -> "#{k}=#{String.slice(v, 0..39)}" end)

      {key, value} when is_binary(value) and value != "" ->
        ["#{key}=#{String.slice(value, 0..39)}"]

      _ ->
        []
    end)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  defp params_summary(_), do: nil

  defp nested_value(params, field) do
    Enum.find_value(params, fn
      {_k, nested} when is_map(nested) -> Map.get(nested, field)
      _ -> nil
    end)
  end

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
    <div class="max-w-6xl mx-auto px-4 py-6">
      <%!-- Header --%>
      <div class="mb-4">
        <.link navigate={@base_path} class="text-sm text-neutral-500 hover:text-neutral-800 transition-colors">← Recordings</.link>
        <h1 class="text-xl font-semibold mt-1 text-pretty">{inspect(@recording.view)}</h1>
        <p class="text-sm text-neutral-500 tabular-nums">
          Session <code class="font-mono text-neutral-600">{String.slice(@recording.id, 0..11)}</code>
          · {length(@recording.events)} events
          · {format_time(@duration_ms)}
        </p>
      </div>

      <%!-- Player --%>
      <div class="bg-white rounded-lg border border-neutral-200 p-4 mb-4">
        <div class="flex items-center gap-1.5 mb-3">
          <button phx-click="step_back" aria-label="Previous event" disabled={@current_index == 0}
            class="p-1.5 rounded-md border border-neutral-200 bg-white text-sm hover:bg-neutral-50 focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-1 disabled:opacity-30 disabled:cursor-default transition-colors">⏮</button>
          <%= if @playing do %>
            <button phx-click="pause" aria-label="Pause"
              class="p-1.5 px-2.5 rounded-md bg-neutral-900 text-white text-sm hover:bg-neutral-800 focus-visible:ring-2 focus-visible:ring-neutral-500 focus-visible:ring-offset-1 transition-colors">⏸</button>
          <% else %>
            <button phx-click="play" aria-label="Play"
              class="p-1.5 px-2.5 rounded-md bg-neutral-900 text-white text-sm hover:bg-neutral-800 focus-visible:ring-2 focus-visible:ring-neutral-500 focus-visible:ring-offset-1 transition-colors">▶</button>
          <% end %>
          <button phx-click="step_forward" aria-label="Next event" disabled={@current_index == last_event_index(@recording)}
            class="p-1.5 rounded-md border border-neutral-200 bg-white text-sm hover:bg-neutral-50 focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-1 disabled:opacity-30 disabled:cursor-default transition-colors">⏭</button>

          <span class="font-mono text-xs text-neutral-500 ml-2 tabular-nums">
            {format_time(current_event_ms(@recording, @current_index))} / {format_time(@duration_ms)}
          </span>

          <span class="flex-1"></span>

          <div class="relative group">
            <button aria-label="Playback speed" class="px-2 py-1 rounded-md border border-neutral-200 bg-white text-xs font-mono hover:bg-neutral-50 focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-1 tabular-nums transition-colors">{@speed}×</button>
            <ul class="hidden group-hover:block absolute bottom-full right-0 bg-white border border-neutral-200 rounded-lg p-1 shadow-lg mb-1 min-w-[3rem]">
              <li :for={s <- [1, 2, 5, 10]} phx-click="speed" phx-value-speed={s}
                class="px-3 py-1 text-xs font-mono rounded cursor-pointer hover:bg-neutral-100 whitespace-nowrap tabular-nums">{s}×</li>
            </ul>
          </div>
        </div>

        <%!-- Scrubber --%>
        <div
          id="rp-scrubber"
          class="relative flex items-center select-none h-5 touch-none cursor-pointer"
          data-duration={@duration_ms}
          phx-update="ignore"
        >
          <div class="relative flex-1 h-1 bg-neutral-200 rounded-full">
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
          <div id="rp-thumb" class="absolute top-1/2 -translate-y-1/2 w-3.5 h-3.5 rounded-full bg-neutral-900 border-2 border-white shadow-sm -translate-x-1/2" style="left:0%;"></div>
        </div>

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

      <%!-- Events + Assigns (always visible, side by side) --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="bg-white rounded-lg border border-neutral-200 flex flex-col min-h-0 min-w-0">
          <div class="px-4 py-2.5 border-b border-neutral-100 flex items-center justify-between shrink-0">
            <h2 class="text-xs font-medium text-neutral-500 uppercase tracking-wide">Events</h2>
            <span class="text-xs text-neutral-400 tabular-nums">{length(@recording.events)}</span>
          </div>
          <div class="overflow-y-auto overscroll-contain p-1.5" style="max-height:clamp(300px, 40vh, 600px);">
            <button
              :for={{event, i} <- Enum.with_index(@recording.events)}
              phx-click="jump"
              phx-value-index={i}
              class={[
                "flex items-center gap-2 w-full text-left text-[13px] leading-snug px-2.5 py-1.5 rounded-md min-w-0 transition-colors",
                if(i == @current_index, do: "bg-neutral-900 text-white", else: "hover:bg-neutral-50"),
                if(i > @current_index and i != @current_index, do: "text-neutral-400")
              ]}
            >
              <span class="shrink-0">{event_icon(elem(event, 1))}</span>
              <span class="flex-1 min-w-0 truncate">{event_label(event)}</span>
              <span class={[
                "shrink-0 font-mono text-[11px] tabular-nums",
                if(i == @current_index, do: "text-neutral-400", else: "text-neutral-300")
              ]}>
                {format_time(elem(event, 0))}
              </span>
            </button>
          </div>
        </div>

        <div class="bg-white rounded-lg border border-neutral-200 flex flex-col min-h-0 min-w-0">
          <div class="px-4 py-2.5 border-b border-neutral-100 shrink-0">
            <h2 class="text-xs font-medium text-neutral-500 uppercase tracking-wide">Assigns</h2>
          </div>
          <pre class="overflow-auto overscroll-contain p-4 text-xs leading-relaxed font-mono text-neutral-700 whitespace-pre-wrap break-words" style="max-height:clamp(300px, 40vh, 600px);"><%= inspect(Recording.accumulated_assigns(@recording, @current_index), pretty: true, limit: 30) %></pre>
        </div>
      </div>
    </div>
    """
  end
end
