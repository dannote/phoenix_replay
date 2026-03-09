import Config

config :phoenix_replay, PhoenixReplay.TestEndpoint,
  http: [port: 4002],
  server: false,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test_salt"]
