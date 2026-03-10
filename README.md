# PhoenixReplay

Session recording and replay for Phoenix LiveView.

![PhoenixReplay dashboard replaying a form session](screenshot.jpg)

LiveView templates are pure functions: same assigns produce the same HTML. PhoenixReplay captures assigns at each state transition and replays them by re-rendering the original view — no client-side recording, no DOM snapshots, no JavaScript changes. A 30-second session with active form input is ~400 events and ~8 KB on disk (ETF + gzip).

## Quick start

Add the dependency:

```elixir
def deps do
  [{:phoenix_replay, "~> 0.1.0"}]
end
```

Attach the recorder to a live session:

```elixir
live_session :default, on_mount: [PhoenixReplay.Recorder] do
  live "/dashboard", DashboardLive
  live "/posts", PostLive.Index
end
```

Mount the replay dashboard:

```elixir
import PhoenixReplay.Router

scope "/" do
  pipe_through :browser
  phoenix_replay "/replay"
end
```

Visit `/replay` to browse recordings and replay sessions with a scrubber, play/pause, and speed controls. Every connected LiveView in the live session is recorded automatically — mount params, events, navigation, and assign deltas. Sessions with no user interaction are discarded.

## How it works

1. The `on_mount` hook attaches lifecycle hooks to each connected LiveView.
2. Session start sends a single async cast to the Store GenServer to set up a process monitor.
3. All subsequent events are written directly to ETS (`ordered_set` with `write_concurrency`) — no GenServer messages on the hot path.
4. When the LiveView process exits, the Store finalizes and persists the recording via the configured storage backend.

### Recorded events

| Event | Data |
|---|---|
| Mount | View module, URL, params, session, initial assigns |
| Handle event | Event name, params |
| Handle params | URL, params |
| Handle info | Type marker only |
| After render | Changed assigns (delta, or full snapshot when batched) |

Each event includes a millisecond offset from session start.

## Configuration

```elixir
config :phoenix_replay,
  max_events: 10_000,
  sanitizer: MyApp.ReplaySanitizer
```

### Storage backends

Active recordings live in ETS. When a LiveView process exits, the recording is persisted via the configured backend.

**File (default):**

```elixir
config :phoenix_replay,
  storage: PhoenixReplay.Storage.File,
  storage_opts: [path: "priv/replay_recordings", format: :etf]
```

**Ecto:**

```elixir
config :phoenix_replay,
  storage: PhoenixReplay.Storage.Ecto,
  storage_opts: [repo: MyApp.Repo, format: :etf]
```

Requires a migration:

```elixir
defmodule MyApp.Repo.Migrations.CreatePhoenixReplayRecordings do
  use Ecto.Migration

  def change do
    create table(:phoenix_replay_recordings, primary_key: false) do
      add :id, :string, primary_key: true
      add :view, :string, null: false
      add :connected_at, :bigint, null: false
      add :event_count, :integer, null: false, default: 0
      add :data, :binary, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
```

Both backends support `:etf` (default — fast, preserves Elixir types) and `:json` (portable but lossy).

### Custom sanitizer

The default sanitizer strips internal LiveView keys and sensitive fields, and compacts `Form`, `Changeset`, and Ecto structs. To customize:

```elixir
defmodule MyApp.ReplaySanitizer do
  @drop [:__changed__, :flash, :uploads, :streams,
         :_replay_id, :_replay_t0, :csrf_token, :password,
         :current_password, :password_confirmation, :token, :secret,
         :my_custom_secret]

  def sanitize_assigns(assigns), do: Map.drop(assigns, @drop)

  def sanitize_delta(changed, assigns) do
    changed
    |> Map.keys()
    |> Enum.reject(&(&1 in @drop))
    |> Map.new(fn key -> {key, Map.get(assigns, key)} end)
  end
end
```

## Manual attachment

To record individual views instead of an entire live session:

```elixir
def mount(params, session, socket) do
  {:ok, PhoenixReplay.Recorder.attach(socket, params, session)}
end
```

## Programmatic access

```elixir
PhoenixReplay.Store.list_recordings()
PhoenixReplay.Store.get_recording(id)
PhoenixReplay.Store.get_active(id)
```

## Roadmap

- Real-time session observation via PubSub
- LiveComponent state tracking
- Configurable sampling (record N% of sessions)
- Session search and filtering

## License

MIT
