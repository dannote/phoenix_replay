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

  ## Configuration

      config :phoenix_replay,
        max_events: 10_000,
        sanitizer: PhoenixReplay.Sanitizer,
        storage: PhoenixReplay.Storage.File,
        storage_opts: [
          path: "priv/replay_recordings",
          format: :etf  # or :json
        ]

  ## Storage backends

    * `PhoenixReplay.Storage.File` — writes one file per recording to disk (default)
    * `PhoenixReplay.Storage.Ecto` — stores recordings in a database table
      (requires `ecto_sql` in the host app)

  Both backends support `:etf` (Erlang Term Format) and `:json` serialization.
  ETF is the default — fast, compact, preserves all Elixir types. JSON is
  portable and human-readable but lossy for atoms, tuples, and structs.

  ### File backend

      config :phoenix_replay,
        storage: PhoenixReplay.Storage.File,
        storage_opts: [path: "priv/replay_recordings", format: :etf]

  ### Ecto backend

      config :phoenix_replay,
        storage: PhoenixReplay.Storage.Ecto,
        storage_opts: [repo: MyApp.Repo, format: :etf]

  See `PhoenixReplay.Storage.Ecto` for the required migration.
  """
end
