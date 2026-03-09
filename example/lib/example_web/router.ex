defmodule ExampleWeb.Router do
  use ExampleWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ExampleWeb do
    pipe_through :browser

    live_session :recorded, on_mount: [PhoenixReplay.Recorder] do
      live "/", TaskLive.Index, :index
      live "/tasks/new", TaskLive.Index, :new
      live "/tasks/:id/edit", TaskLive.Index, :edit
    end

    live_session :replay do
      live "/replay", ReplayLive.Index
      live "/replay/:id", ReplayLive.Show
    end
  end
end
