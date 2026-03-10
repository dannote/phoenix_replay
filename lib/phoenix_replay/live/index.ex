defmodule PhoenixReplay.Live.Index do
  @moduledoc false
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
    active = Store.list_active()
    finished = Store.list_recordings()
    active ++ finished
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
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-2xl font-bold">📹 PhoenixReplay</h1>
        <span class="text-sm text-neutral-500">
          {length(@recordings)} recording{if length(@recordings) != 1, do: "s"}
        </span>
      </div>

      <div :if={@recordings == []} class="text-center py-16 text-neutral-400">
        <div class="text-5xl mb-4">📹</div>
        <p>No recordings yet.</p>
        <p class="text-sm mt-1">
          Add <code class="font-mono text-neutral-600">on_mount: [PhoenixReplay.Recorder]</code> to a live_session and start using your app.
        </p>
      </div>

      <.link
        :for={rec <- @recordings}
        navigate={"#{@base_path}/#{rec.id}"}
        class="block bg-white rounded-lg border border-neutral-200 mb-3 hover:shadow-md transition-shadow no-underline text-inherit"
      >
        <div class="px-5 py-4 flex items-center justify-between">
          <div>
            <div class="font-medium flex items-center gap-2">
              {inspect(rec.view)}
              <span :if={active?(rec)} class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-green-100 text-green-800">
                <span class="inline-block w-2 h-2 bg-green-500 rounded-full animate-pulse" /> LIVE
              </span>
            </div>
            <div class="text-sm text-neutral-500 mt-1">
              Started at {format_time(rec.connected_at)}
              · {length(rec.events)} events
              · {format_duration(duration_ms(rec))}
            </div>
          </div>
          <div class="font-mono text-sm text-neutral-400">
            {String.slice(rec.id, 0..7)}
          </div>
        </div>
      </.link>
    </div>
    """
  end
end
