defmodule PhoenixReplay.Live.Frame do
  @moduledoc """
  Renders the original view's template with recorded assigns.

  Mounted inside an iframe on the replay page. Listens for
  `{:replay_jump, index}` messages via PubSub to step through
  the recording and re-render at each point.
  """

  use Phoenix.LiveView

  alias PhoenixReplay.{Recording, Store}

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    recording = fetch_recording!(id)
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
      _ ->
        ~H"""
        <div style="padding:2rem; color:#737373; text-align:center;">
          <p>Could not render {inspect(@_recording.view)} at this point.</p>
          <p style="font-size:0.875rem;">Some assigns may be missing for this event.</p>
        </div>
        """
    end
  end

  defp fetch_recording!(id) do
    case Store.get_recording(id) do
      {:ok, rec} ->
        rec

      :error ->
        case Store.get_active(id) do
          {:ok, rec} -> rec
          :error -> raise "Recording not found: #{id}"
        end
    end
  end

  defp inject_assigns(socket, recorded_assigns) do
    Enum.reduce(recorded_assigns, socket, fn {key, value}, sock ->
      Phoenix.Component.assign(sock, key, value)
    end)
  end

  defp first_renderable_index(recording) do
    Enum.find_index(recording.events, fn
      {_, :assigns, _} -> true
      _ -> false
    end) || 0
  end

  defp parse_index(nil), do: 0
  defp parse_index(val) when is_binary(val), do: String.to_integer(val)
  defp parse_index(val) when is_integer(val), do: val
end
