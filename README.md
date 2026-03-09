# PhoenixReplay

Session recording and replay for Phoenix LiveView — no client-side JS, no rrweb, just BEAM.

LiveView templates are pure functions: same assigns → same HTML. PhoenixReplay captures assigns at each state transition, so replay is just injecting them back. The database is never consulted.

## Installation

```elixir
def deps do
  [
    {:phoenix_replay, "~> 0.1.0"}
  ]
end
```

## Usage

Add the recorder hook to your `live_session`:

```elixir
live_session :default, on_mount: [PhoenixReplay.Recorder] do
  live "/dashboard", DashboardLive
  live "/posts", PostLive.Index
end
```

That's it. Every connected LiveView session is now recorded — mount params, events, navigation, and assigns deltas.

Recordings are stored in ETS and finalized automatically when the LiveView process exits.

### Manual attachment

If you don't want to record all views in a live_session:

```elixir
def mount(_params, _session, socket) do
  {:ok, PhoenixReplay.Recorder.attach(socket)}
end
```

### Accessing recordings

```elixir
# List all completed recordings
PhoenixReplay.Store.list_recordings()

# Get a specific recording
PhoenixReplay.Store.get_recording(id)

# Peek at an active (in-progress) recording
PhoenixReplay.Store.get_active(id)
```

## What gets recorded

For each session:

| Event | Data |
|---|---|
| Mount | View module, URL, params, session, initial assigns |
| Handle event | Event name, params |
| Handle params | URL, params |
| Handle info | (type marker only) |
| After render | Changed assigns (delta only) |

Each event includes a millisecond offset from session start.

A 10-minute session with active interaction is typically ~500 events ≈ 50KB.
Compare that to rrweb which generates 5-50MB per session.

## Configuration

```elixir
config :phoenix_replay,
  max_events: 10_000,       # cap per session (default: 10,000)
  sanitizer: MyApp.Sanitizer # custom assigns filter (default: PhoenixReplay.Sanitizer)
```

### Custom sanitizer

The default sanitizer strips `__changed__`, `flash`, `uploads`, `streams`, `csrf_token`, `password`, `token`, and `secret`. To customize:

```elixir
defmodule MyApp.ReplaySanitizer do
  def sanitize_assigns(assigns) do
    Map.drop(assigns, [:__changed__, :flash, :secret_field])
  end

  def sanitize_delta(changed, assigns) do
    changed
    |> Map.keys()
    |> Enum.reject(&(&1 in [:__changed__, :flash, :secret_field]))
    |> Map.new(fn key -> {key, Map.get(assigns, key)} end)
  end
end
```

## How it works

1. An `on_mount` hook attaches lifecycle hooks to each connected LiveView
2. Events are written directly to ETS (`ordered_set` with `write_concurrency`) — zero backpressure on the LiveView process
3. The Store GenServer monitors each LiveView PID and auto-finalizes the recording on process exit
4. Recordings are moved to a separate read-optimized ETS table

No messages are sent during recording. The LiveView process writes to ETS and continues immediately.

## Roadmap

- [ ] Replay viewer LiveView component (scrubber, play/pause, speed control)
- [ ] Persistent storage backends (Postgres, files)
- [ ] Session search and filtering
- [ ] Real-time session observation via PubSub
- [ ] LiveComponent state tracking
- [ ] Configurable sampling (record N% of sessions)

## License

MIT
