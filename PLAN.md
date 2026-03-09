# PhoenixReplay

Session recording and replay for Phoenix LiveView. No client-side JS, no rrweb — just BEAM.

## Core Insight

LiveView templates are pure functions: same assigns → same HTML. Record the assigns at each state transition, replay by injecting them back. The database is never consulted during replay.

## Architecture

### Capture Layer

**`on_mount` hook** that attaches lifecycle hooks per socket:

- `:handle_event` — log event name + params
- `:handle_params` — log navigation (patches, URL changes)
- `:after_render` — snapshot changed assigns (delta only, via `__changed__`)
- mount itself — capture initial params, session, URL, full assigns

**Telemetry handlers** (global, for timing/metadata):

- `[:phoenix, :live_view, :mount, :start/:stop]`
- `[:phoenix, :live_view, :handle_event, :start/:stop]`
- `[:phoenix, :live_view, :render, :start/:stop]`

### Storage Layer

**Hot path:** ETS table with `:write_concurrency` — the LiveView process writes events without blocking.

**Cold path:** A GenServer (or Broadway pipeline) batch-flushes from ETS to persistent storage.

**Recording format:**

```elixir
%PhoenixReplay.Recording{
  session_id: "...",
  view: MyAppWeb.DashboardLive,
  connected_at: ~U[...],
  initial_url: "/dashboard",
  initial_params: %{},
  initial_session: %{},  # filtered for PII
  events: [
    # {ms_offset, type, payload}
    {0,    :mount,         %{assigns: %{user: ..., posts: [...], page: 1}}},
    {340,  :event,         %{name: "next_page", params: %{}, assigns_delta: %{page: 2, posts: [...]}}},
    {890,  :event,         %{name: "delete", params: %{"id" => "5"}, assigns_delta: %{posts: [...]}}},
    {1200, :handle_params, %{url: "/dashboard?tab=settings", assigns_delta: %{live_action: :settings}}},
  ]
}
```

~100 bytes per event. A 10-min active session ≈ 500 events ≈ 50KB (vs rrweb's 5-50MB).

### Replay Layer

**Server-side replay LiveView:**

1. Mount a lightweight LiveView that uses the **same template** as the recorded view
2. At each step, inject the recorded assigns into the socket
3. The template renders exactly what the user saw
4. Scrubber UI to step through, play/pause, adjust speed

**Alternative: client-only replay:**

1. Capture the diff maps from `push_diff` at transport level
2. Replay diffs in a standalone HTML page using LiveView's JS morphdom logic
3. Zero server cost during replay

## LiveView Internals — Hook Points

### The LiveView Channel Process (`Phoenix.LiveView.Channel`)

- It's a `GenServer` (restart: :temporary)
- State: `%{socket:, fingerprints:, components:, topic:, serializer:, ...}`
- All user events arrive as `%Phoenix.Socket.Message{event: "event"}` in `handle_info`
- After any callback, `handle_changed/3` → `render_diff/3` → `push_diff/3` sends the diff to the client
- `push_diff` calls `push(state, "diff", diff)` which sends encoded message to `transport_pid`

### `Phoenix.LiveView.Socket` struct

```elixir
%Socket{
  assigns: %{__changed__: %{}},  # __changed__ tracks which keys were modified
  view: MyAppWeb.SomeLive,
  endpoint: MyAppWeb.Endpoint,
  router: MyAppWeb.Router,
  id: "...",
  transport_pid: pid,
  parent_pid: nil | pid,
  root_pid: pid,
}
```

### `Phoenix.LiveView.Lifecycle`

Supports `attach_hook/4` for: `:handle_event`, `:handle_info`, `:handle_params`, `:handle_async`, `:after_render`. Also `on_mount` hooks via `live_session`.

### Telemetry Events (with metadata)

| Event | Metadata |
|---|---|
| `[:phoenix, :live_view, :mount, :start/:stop]` | socket, params, session, uri |
| `[:phoenix, :live_view, :handle_params, :start/:stop]` | socket, params, uri |
| `[:phoenix, :live_view, :handle_event, :start/:stop]` | socket, event, params |
| `[:phoenix, :live_view, :render, :start/:stop]` | socket, force?, changed? |
| `[:phoenix, :live_component, :handle_event, :start/:stop]` | socket, component, event, params |
| `[:phoenix, :live_component, :update, :start/:stop]` | socket, component, assigns_sockets |

### `Phoenix.LiveView.Debug` (runtime)

- `list_liveviews/0` — all LV processes on the node
- `socket/1` — get socket of any LV by PID
- `live_components/1` — inspect components in a LV

## BEAM Superpowers

1. **Per-session GenServer** — one recording process per session, millions supported, hibernate when idle
2. **ETS with `:write_concurrency`** — zero-backpressure writes from LV processes
3. **`:erlang.trace/3`** — trace specific LV processes without code changes (ad-hoc recording mode)
4. **PubSub** — broadcast events for real-time session observation (support engineer watches live)
5. **`:persistent_term`** — store recording config (which views, sampling rate, field filters) with zero read cost

## Sensitive Data

- Filter assigns before recording (configurable allowlist/denylist per view)
- Strip session tokens, CSRF tokens
- Option to hash or redact specific fields
- Recording opt-in per view module or per user

## Edge Cases

- **JS hooks / client-side JS** — not captured; replay shows server-side state only
- **File uploads** — record the upload metadata, not the file content
- **LiveComponents** — assigns are tracked per-component via CID, need to capture component state too
- **Live streams** — stream items are ephemeral; snapshot the stream state in assigns
- **`push_event`** — record JS events pushed from server for completeness

## Implementation Order

1. `PhoenixReplay.Recorder` — on_mount hook + ETS capture
2. `PhoenixReplay.Storage` — GenServer that flushes ETS to disk/DB
3. `PhoenixReplay.Sanitizer` — configurable field filtering
4. `PhoenixReplay.Player` — LiveView component for replay with scrubber
5. `PhoenixReplay.Dashboard` — list/search recorded sessions
