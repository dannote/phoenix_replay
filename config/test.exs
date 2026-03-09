import Config

config :phoenix_replay, PhoenixReplay.TestEndpoint,
  http: [port: 4002],
  server: false,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test_salt"]

config :phoenix_replay,
  storage: PhoenixReplay.Storage.File,
  storage_opts: [
    path: Path.join(System.tmp_dir!(), "phoenix_replay_test"),
    format: :etf
  ]
