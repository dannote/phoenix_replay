defmodule PhoenixReplay do
  @moduledoc """
  Session recording and replay for Phoenix LiveView.

  PhoenixReplay captures LiveView state transitions (events, navigation, assigns changes)
  and enables exact replay without any client-side recording library.

  ## Setup

  Add the recorder hook to your `live_session`:

      live_session :default, on_mount: [PhoenixReplay.Recorder] do
        live "/dashboard", DashboardLive
      end

  Or attach it in a specific LiveView:

      def mount(_params, _session, socket) do
        {:ok, PhoenixReplay.Recorder.attach(socket)}
      end

  ## Configuration

      config :phoenix_replay,
        # Maximum events per recording (prevents runaway sessions)
        max_events: 10_000,
        # How long to keep recordings in ETS before flushing
        flush_interval_ms: 5_000,
        # Filter assigns before recording
        sanitizer: PhoenixReplay.Sanitizer,
        # Storage backend
        storage: PhoenixReplay.Storage.ETS
  """
end
