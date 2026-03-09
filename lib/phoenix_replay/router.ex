defmodule PhoenixReplay.Router do
  @moduledoc """
  Provides routing for the PhoenixReplay dashboard.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import PhoenixReplay.Router

        scope "/" do
          pipe_through :browser
          phoenix_replay "/replay"
        end
      end
  """

  @doc """
  Mounts the PhoenixReplay dashboard at the given path.
  """
  defmacro phoenix_replay(path, opts \\ []) do
    quote bind_quoted: binding() do
      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        live_session :phoenix_replay,
          root_layout: {PhoenixReplay.Layouts, :root} do
          live("/", PhoenixReplay.Live.Index, :index, as: :replay_index)
          live("/:id", PhoenixReplay.Live.Show, :show, as: :replay_show)
        end

        live_session :phoenix_replay_frame,
          root_layout: {PhoenixReplay.Layouts, :frame} do
          live("/:id/frame", PhoenixReplay.Live.Frame, :frame, as: :replay_frame)
        end
      end
    end
  end
end
