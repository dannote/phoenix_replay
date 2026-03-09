defmodule PhoenixReplay.TestRouter do
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import PhoenixReplay.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)

    live_session :recorded, on_mount: [PhoenixReplay.Recorder] do
      live("/counter", PhoenixReplay.TestLive.Counter)
    end

    phoenix_replay("/replay")
  end
end
