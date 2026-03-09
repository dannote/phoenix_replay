defmodule ExampleWeb.ReplayLive.Show do
  use ExampleWeb, :live_view

  alias PhoenixReplay.Store

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
       |> assign(:current_index, 0)
       |> assign(:playing, false)
       |> assign(:speed, 1)}
    else
      {:ok, push_navigate(socket, to: ~p"/replay")}
    end
  end

  @impl true
  def handle_event("step_forward", _, socket) do
    max = length(socket.assigns.recording.events) - 1
    index = min(socket.assigns.current_index + 1, max)
    {:noreply, assign(socket, :current_index, index)}
  end

  def handle_event("step_back", _, socket) do
    index = max(socket.assigns.current_index - 1, 0)
    {:noreply, assign(socket, :current_index, index)}
  end

  def handle_event("jump", %{"index" => index}, socket) do
    {:noreply, assign(socket, :current_index, String.to_integer(index))}
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
      {:noreply, assign(socket, :current_index, index + 1)}
    else
      {:noreply, assign(socket, :playing, false)}
    end
  end

  defp current_event(recording, index) do
    Enum.at(recording.events, index)
  end

  defp accumulated_assigns(recording, index) do
    recording.events
    |> Enum.take(index + 1)
    |> Enum.reduce(%{}, fn
      {_, :mount, %{assigns: assigns}}, _acc -> assigns
      {_, :assigns, %{delta: delta}}, acc -> Map.merge(acc, delta)
      _, acc -> acc
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

  defp format_offset(ms) do
    seconds = div(ms, 1000)
    millis = rem(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    cond do
      minutes > 0 ->
        "#{minutes}:#{String.pad_leading("#{secs}", 2, "0")}.#{String.pad_leading("#{millis}", 3, "0")}"

      true ->
        "#{secs}.#{String.pad_leading("#{millis}", 3, "0")}s"
    end
  end
end
