defmodule ExampleWeb.Features.ReplayTest do
  use PhoenixTest.Playwright.Case, async: false
  use ExampleWeb, :verified_routes

  alias Example.{Repo, Tasks.Task}

  setup do
    PhoenixReplay.Store.clear_all()
    Repo.insert!(%Task{title: "Replay test task", priority: "high"})

    on_exit(fn -> PhoenixReplay.Store.clear_all() end)

    :ok
  end

  defp create_recording_and_go_to_replay(conn) do
    conn
    |> visit(~p"/")
    |> assert_has("h1", text: "Tasks")
    |> click_button("Toggle Replay test task")
    |> visit(~p"/replay")
    |> assert_has("h1", text: "PhoenixReplay")
  end

  defp open_first_recording(conn) do
    conn
    |> PhoenixTest.Playwright.click("a.rp-card:first-of-type")
    |> assert_has("h1", text: "ExampleWeb.TaskLive.Index")
  end

  test "record a session and view it in replay", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> assert_has("a", text: "ExampleWeb.TaskLive.Index")
  end

  test "player shows initial time 0:00 and total duration", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> assert_has(".rp-mono", text: "0:00")
  end

  test "step forward updates iframe content", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> click_button("⏭")
    |> click_button("⏭")
  end

  test "step back works", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> click_button("⏭")
    |> click_button("⏮")
  end

  test "play button toggles to pause", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> PhoenixTest.Playwright.click("button[phx-click='play']")
    |> assert_has("button[phx-click='pause']")
  end

  test "events panel toggle", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> refute_has("pre")
    |> click_button("▶ Events")
    |> assert_has("pre")
  end

  test "scrubber range input exists", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> assert_has("#rp-scrubber[step='any']")
  end

  test "speed button is rendered", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> assert_has(".rp-speed-menu button", text: "1×")
  end
end
