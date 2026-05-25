defmodule PhoenixReplay.Live.Frame do
  @moduledoc """
  Renders the original view's template with recorded assigns.

  Mounted inside an iframe on the replay page. Listens for
  `{:replay_jump, index}` messages via PubSub to step through
  the recording and re-render at each point.
  """

  use Phoenix.LiveView

  alias PhoenixReplay.{Recording, Recordings}

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    recording = Recordings.fetch!(id)
    index = parse_index(params["index"])
    index = max(index, first_renderable_index(recording))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(PhoenixReplay.PubSub, "replay:#{id}")
    end

    assigns = Recording.accumulated_assigns(recording, index)

    {:ok,
     socket
     |> assign(:_recording, recording)
     |> assign(:_current_index, index)
     |> assign(:_recorded_assign_keys, MapSet.new())
     |> inject_assigns(assigns), layout: false}
  end

  @impl true
  def handle_info({:replay_jump, index}, socket) do
    recording = socket.assigns._recording
    min_index = first_renderable_index(recording)
    max = length(recording.events) - 1
    index = max(min_index, min(index, max))
    assigns = Recording.accumulated_assigns(recording, index)

    {:noreply,
     socket
     |> assign(:_current_index, index)
     |> inject_assigns(assigns)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    view = assigns._recording.view

    try do
      view.render(assigns)
    rescue
      e in [
        ArgumentError,
        FunctionClauseError,
        KeyError,
        MatchError,
        Protocol.UndefinedError,
        RuntimeError,
        UndefinedFunctionError
      ] ->
        require Logger

        Logger.warning(
          "PhoenixReplay: render failed for #{inspect(view)}: #{Exception.message(e)}"
        )

        ~H"""
        <div style="padding:2rem; color:#737373; text-align:center;">
          <p>Could not render {inspect(@_recording.view)} at this point.</p>
          <p style="font-size:0.875rem;">Some assigns may be missing for this event.</p>
        </div>
        """
    end
  end

  defp inject_assigns(socket, recorded_assigns) do
    previous_keys = socket.assigns[:_recorded_assign_keys] || MapSet.new()
    next_keys = recorded_assigns |> Map.keys() |> MapSet.new()

    socket
    |> clear_stale_assigns(MapSet.difference(previous_keys, next_keys))
    |> assign(:_recorded_assign_keys, next_keys)
    |> then(fn sock ->
      Enum.reduce(recorded_assigns, sock, fn {key, value}, acc ->
        Phoenix.Component.assign(acc, key, value)
      end)
    end)
  end

  defp clear_stale_assigns(socket, keys) do
    Enum.reduce(keys, socket, fn key, acc ->
      Phoenix.Component.assign(acc, key, nil)
    end)
  end

  defp first_renderable_index(recording) do
    Enum.find_index(recording.events, fn
      {_, :assigns, _} -> true
      _ -> false
    end) || 0
  end

  defp parse_index(nil), do: 0

  defp parse_index(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> 0
    end
  end

  defp parse_index(val) when is_integer(val), do: val
  defp parse_index(_val), do: 0
end
