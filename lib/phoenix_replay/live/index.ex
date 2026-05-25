defmodule PhoenixReplay.Live.Index do
  @moduledoc false
  use Phoenix.LiveView

  alias PhoenixReplay.{Recordings, Store}

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(2000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "PhoenixReplay")
     |> assign(:base_path, "")
     |> assign(:page, 1)
     |> assign_recordings()}
  end

  @impl true
  def handle_params(params, url, socket) do
    base_path = url |> URI.parse() |> Map.get(:path, "") |> String.trim_trailing("/")
    page = parse_page(params["page"])

    {:noreply,
     socket
     |> assign(:base_path, base_path)
     |> assign(:page, page)
     |> assign_recordings()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign_recordings(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    Store.delete_recording(id)
    {:noreply, assign_recordings(socket)}
  end

  def handle_event("clear_all", _params, socket) do
    Store.clear_all()
    {:noreply, assign_recordings(socket)}
  end

  defp assign_recordings(socket) do
    all = list_all()
    page = min(socket.assigns[:page] || 1, total_pages(all))

    socket
    |> assign(:page, page)
    |> assign(:total_recordings, length(all))
    |> assign(:total_pages, total_pages(all))
    |> assign(:recordings, paginate(all, page))
  end

  defp list_all do
    Recordings.list_summaries()
  end

  defp paginate(recordings, page) do
    Enum.slice(recordings, (page - 1) * @per_page, @per_page)
  end

  defp total_pages(recordings), do: max(1, ceil(length(recordings) / @per_page))

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} -> max(page, 1)
      _ -> 1
    end
  end

  defp parse_page(_page), do: 1

  defp format_time(ms) when is_integer(ms) do
    DateTime.from_unix!(ms, :millisecond) |> Calendar.strftime("%H:%M:%S")
  end

  defp duration_ms(%{duration_ms: nil}), do: 0
  defp duration_ms(%{duration_ms: ms}) when is_integer(ms), do: ms

  defp format_duration(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    if minutes > 0, do: "#{minutes}m #{secs}s", else: "#{secs}s"
  end

  defp active?(recording), do: recording.active?

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-2xl font-bold">📹 PhoenixReplay</h1>
        <span class="text-sm text-neutral-500">
          {@total_recordings} recording{if @total_recordings != 1, do: "s"}
        </span>
      </div>

      <button :if={@total_recordings > 0} phx-click="clear_all" class="mb-4 px-3 py-1.5 rounded-md border border-red-200 bg-white text-sm text-red-700 hover:bg-red-50">
        Clear all recordings
      </button>

      <div :if={@recordings == []} class="text-center py-16 text-neutral-400">
        <div class="text-5xl mb-4">📹</div>
        <p>No recordings yet.</p>
        <p class="text-sm mt-1">
          Add <code class="font-mono text-neutral-600">on_mount: [PhoenixReplay.Recorder]</code> to a live_session and start using your app.
        </p>
      </div>

      <div
        :for={rec <- @recordings}
        class="bg-white rounded-lg border border-neutral-200 mb-3 hover:shadow-md transition-shadow"
      >
        <div class="px-5 py-4 flex items-center justify-between gap-4">
          <div>
            <div class="font-medium flex items-center gap-2">
              {inspect(rec.view)}
              <span :if={active?(rec)} class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-green-100 text-green-800">
                <span class="inline-block w-2 h-2 bg-green-500 rounded-full animate-pulse" /> LIVE
              </span>
            </div>
            <div class="text-sm text-neutral-500 mt-1">
              Started at {format_time(rec.connected_at)}
              · {rec.event_count} events
              · {format_duration(duration_ms(rec))}
            </div>
          </div>
          <div class="flex items-center gap-3">
            <div class="font-mono text-sm text-neutral-400">
              {String.slice(rec.id, 0..7)}
            </div>
            <.link navigate={"#{@base_path}/#{rec.id}"} class="px-2 py-1 rounded border border-neutral-200 text-xs text-neutral-700 hover:bg-neutral-50 no-underline">
              Open
            </.link>
            <button :if={!active?(rec)} phx-click="delete" phx-value-id={rec.id} class="px-2 py-1 rounded border border-red-200 text-xs text-red-700 hover:bg-red-50">
              Delete
            </button>
          </div>
        </div>
      </div>

      <div :if={@total_pages > 1} class="flex items-center justify-center gap-3 mt-6 text-sm">
        <.link :if={@page > 1} patch={"#{@base_path}?page=#{@page - 1}"} class="text-neutral-600 hover:text-neutral-900">← Previous</.link>
        <span class="text-neutral-400">Page {@page} / {@total_pages}</span>
        <.link :if={@page < @total_pages} patch={"#{@base_path}?page=#{@page + 1}"} class="text-neutral-600 hover:text-neutral-900">Next →</.link>
      </div>
    </div>
    """
  end
end
