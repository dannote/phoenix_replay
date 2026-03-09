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

  test "player controls: step forward and back", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> click_button("⏭")
    |> click_button("⏮")
  end

  test "events panel toggle", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> refute_has("pre")
    |> click_button("▶ Events")
    |> assert_has("pre")
  end

  test "time display shows current and total time", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> assert_has("span", text: "0:00")
  end

  test "scrubber range input exists", %{conn: conn} do
    conn
    |> create_recording_and_go_to_replay()
    |> open_first_recording()
    |> assert_has("#scrubber input[type=range]")
  end
end
