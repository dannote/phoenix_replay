defmodule PhoenixReplay.RecordingsTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.{Recording, Recordings}

  test "summary returns lightweight recording metadata" do
    recording = recording()

    assert Recordings.summary(recording) == %{
             id: "rec",
             view: PhoenixReplay.TestLive.Counter,
             url: "/counter",
             connected_at: 1000,
             event_count: 3,
             duration_ms: 250,
             active?: false
           }
  end

  test "active_summary marks recording active" do
    assert %{active?: true} = Recordings.active_summary(recording())
  end

  test "event_offsets returns event timeline indices" do
    assert Recordings.event_offsets(recording()) == [
             %{ms: 0, index: 0},
             %{ms: 100, index: 1},
             %{ms: 250, index: 2}
           ]
  end

  test "total_duration returns last event offset" do
    assert Recordings.total_duration(recording()) == 250
    assert Recordings.total_duration(%Recording{events: []}) == 0
  end

  defp recording do
    %Recording{
      id: "rec",
      view: PhoenixReplay.TestLive.Counter,
      url: "/counter",
      params: %{},
      session: %{},
      connected_at: 1000,
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {100, :event, %{name: "inc", params: %{}}},
        {250, :assigns, %{delta: %{count: 1}}}
      ]
    }
  end
end
