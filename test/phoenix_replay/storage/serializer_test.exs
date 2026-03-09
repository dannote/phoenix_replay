defmodule PhoenixReplay.Storage.SerializerTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Storage.Serializer

  defp sample_recording do
    %Recording{
      id: "test-123",
      view: PhoenixReplay.TestLive.Counter,
      url: "http://localhost/counter",
      params: %{},
      session: %{},
      connected_at: 1_700_000_000_000,
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {100, :event, %{name: "inc"}},
        {200, :assigns, %{delta: %{count: 1}}}
      ]
    }
  end

  test "ETF roundtrip preserves all data" do
    rec = sample_recording()
    {:ok, encoded} = Serializer.encode(rec, :etf)
    {:ok, decoded} = Serializer.decode(encoded, :etf)

    assert decoded.id == rec.id
    assert decoded.view == rec.view
    assert decoded.connected_at == rec.connected_at
    assert decoded.events == rec.events
  end

  test "JSON roundtrip preserves essential data" do
    rec = sample_recording()
    {:ok, encoded} = Serializer.encode(rec, :json)
    assert is_binary(encoded)
    assert String.contains?(encoded, "test-123")

    {:ok, decoded} = Serializer.decode(encoded, :json)
    assert decoded.id == rec.id
    assert decoded.view == rec.view
    assert decoded.connected_at == rec.connected_at
    assert length(decoded.events) == 3

    {offset, type, _payload} = hd(decoded.events)
    assert offset == 0
    assert type == :mount
  end

  test "JSON output is valid JSON" do
    rec = sample_recording()
    {:ok, encoded} = Serializer.encode(rec, :json)
    assert {:ok, _} = Jason.decode(encoded)
  end

  test "ETF extension" do
    assert Serializer.extension(:etf) == ".etf"
  end

  test "JSON extension" do
    assert Serializer.extension(:json) == ".json"
  end
end
