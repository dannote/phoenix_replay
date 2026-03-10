defmodule PhoenixReplay.Recorder do
  @moduledoc """
  LiveView lifecycle hook that records session state transitions.

  ## Usage as on_mount hook

      live_session :default, on_mount: [PhoenixReplay.Recorder] do
        live "/dashboard", DashboardLive
      end

  ## Manual attachment

      def mount(_params, _session, socket) do
        {:ok, PhoenixReplay.Recorder.attach(socket)}
      end
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias PhoenixReplay.{Recording, Store}

  @doc """
  `on_mount` callback. Automatically attaches recording hooks.
  """
  def on_mount(:default, params, session, socket) do
    if connected?(socket) do
      {:cont, start_and_attach(socket, params, session)}
    else
      {:cont, socket}
    end
  end

  @doc """
  Manually attach recording to a socket. Use when not using `on_mount`.

  Pass `params` and `session` from your `mount/3` to capture them in the
  recording. If omitted, they are recorded as empty maps.

  ## Examples

      def mount(params, session, socket) do
        {:ok, PhoenixReplay.Recorder.attach(socket, params, session)}
      end

  """
  def attach(socket, params \\ %{}, session \\ %{}) do
    if connected?(socket) do
      start_and_attach(socket, params, session)
    else
      socket
    end
  end

  defp start_and_attach(socket, params, session) do
    id = generate_id()
    now = System.monotonic_time(:millisecond)
    sanitizer = sanitizer_mod()

    recording = %Recording{
      id: id,
      view: socket.view,
      url: get_url(socket),
      params: params,
      session: sanitizer.sanitize_assigns(session),
      connected_at: System.system_time(:millisecond),
      events: [
        {0, :mount, %{assigns: sanitizer.sanitize_assigns(socket.assigns)}}
      ]
    }

    Store.start_recording(id, recording)

    socket
    |> assign(:_replay_id, id)
    |> assign(:_replay_t0, now)
    |> attach_hook(:_replay_event, :handle_event, &handle_event_hook/3)
    |> attach_hook(:_replay_params, :handle_params, &handle_params_hook/3)
    |> attach_hook(:_replay_info, :handle_info, &handle_info_hook/2)
    |> attach_hook(:_replay_render, :after_render, &after_render_hook/1)
  end

  defp handle_event_hook(event, params, socket) do
    bump_pending_events(socket)
    record(socket, :event, %{name: event, params: params})
    {:cont, socket}
  end

  defp handle_params_hook(params, url, socket) do
    record(socket, :handle_params, %{params: params, url: url})
    {:cont, socket}
  end

  defp handle_info_hook(_msg, socket) do
    record(socket, :info, %{})
    {:cont, socket}
  end

  defp after_render_hook(socket) do
    changed = socket.assigns.__changed__
    pending = get_pending_events(socket)

    if changed != %{} do
      sanitizer = sanitizer_mod()
      delta = sanitizer.sanitize_delta(changed, socket.assigns)

      if delta != %{} do
        if pending > 1 do
          full = sanitizer.sanitize_assigns(socket.assigns)
          record(socket, :assigns, %{snapshot: full})
        else
          record(socket, :assigns, %{delta: delta})
        end
      end
    end

    reset_pending_events(socket)
    socket
  end

  defp bump_pending_events(socket) do
    key = {:replay_pending, socket.assigns[:_replay_id]}
    Process.put(key, (Process.get(key) || 0) + 1)
  end

  defp get_pending_events(socket) do
    Process.get({:replay_pending, socket.assigns[:_replay_id]}) || 0
  end

  defp reset_pending_events(socket) do
    Process.put({:replay_pending, socket.assigns[:_replay_id]}, 0)
  end

  defp record(socket, type, payload) do
    id = socket.assigns[:_replay_id]
    t0 = socket.assigns[:_replay_t0]

    if id && t0 do
      offset = System.monotonic_time(:millisecond) - t0
      Store.append_event(id, {offset, type, payload})
    end
  end

  defp get_url(socket) do
    case socket.host_uri do
      %URI{} = uri -> URI.to_string(uri)
      _ -> nil
    end
  end

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  defp sanitizer_mod do
    Application.get_env(:phoenix_replay, :sanitizer, PhoenixReplay.Sanitizer)
  end
end
