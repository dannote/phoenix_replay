defmodule PhoenixReplay.Storage.Serializer do
  @moduledoc false

  alias PhoenixReplay.Recording

  @doc "Encode a recording to binary in the given format."
  @spec encode(Recording.t(), :etf | :json) :: {:ok, binary()} | {:error, term()}
  def encode(recording, :etf) do
    {:ok, :erlang.term_to_binary(to_map(recording))}
  end

  def encode(recording, :json) do
    recording |> to_json_map() |> Jason.encode()
  end

  @doc "Decode binary back to a Recording struct."
  @spec decode(binary(), :etf | :json) :: {:ok, Recording.t()} | {:error, term()}
  def decode(binary, :etf) do
    {:ok, binary |> :erlang.binary_to_term([:safe]) |> from_map()}
  rescue
    e -> {:error, e}
  end

  def decode(binary, :json) do
    case Jason.decode(binary) do
      {:ok, map} -> {:ok, from_json_map(map)}
      error -> error
    end
  end

  @doc "File extension for the format."
  @spec extension(:etf | :json) :: String.t()
  def extension(:etf), do: ".etf"
  def extension(:json), do: ".json"

  defp to_map(%Recording{} = rec) do
    %{
      id: rec.id,
      view: rec.view,
      url: rec.url,
      params: rec.params,
      session: rec.session,
      connected_at: rec.connected_at,
      events: rec.events
    }
  end

  defp from_map(map) do
    %Recording{
      id: map.id,
      view: map.view,
      url: map.url,
      params: map.params,
      session: map.session,
      connected_at: map.connected_at,
      events: map.events
    }
  end

  defp to_json_map(%Recording{} = rec) do
    %{
      "id" => rec.id,
      "view" => inspect(rec.view),
      "url" => rec.url,
      "params" => rec.params,
      "session" => rec.session,
      "connected_at" => rec.connected_at,
      "events" => Enum.map(rec.events, &event_to_json/1)
    }
  end

  defp event_to_json({offset, type, payload}) do
    %{
      "offset" => offset,
      "type" => to_string(type),
      "payload" => payload_to_json(payload)
    }
  end

  defp payload_to_json(payload) when is_map(payload) do
    Map.new(payload, fn
      {k, v} when is_atom(k) -> {to_string(k), payload_value_to_json(v)}
      {k, v} -> {k, payload_value_to_json(v)}
    end)
  end

  defp payload_value_to_json(v) when is_atom(v), do: to_string(v)
  defp payload_value_to_json(v) when is_map(v), do: payload_to_json(v)
  defp payload_value_to_json(v) when is_list(v), do: Enum.map(v, &payload_value_to_json/1)

  defp payload_value_to_json(v) when is_tuple(v),
    do: Tuple.to_list(v) |> Enum.map(&payload_value_to_json/1)

  defp payload_value_to_json(v), do: v

  defp from_json_map(map) do
    %Recording{
      id: map["id"],
      view: resolve_module(map["view"]),
      url: map["url"],
      params: map["params"] || %{},
      session: map["session"] || %{},
      connected_at: map["connected_at"],
      events: Enum.map(map["events"] || [], &event_from_json/1)
    }
  end

  defp event_from_json(%{"offset" => offset, "type" => type, "payload" => payload}) do
    {offset, String.to_existing_atom(type), payload}
  end

  defp resolve_module(name) when is_binary(name) do
    name = String.trim_leading(name, "Elixir.")
    String.to_existing_atom("Elixir." <> name)
  rescue
    _ -> name
  end
end
