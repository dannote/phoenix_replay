defmodule PhoenixReplay.Sanitizer do
  @moduledoc """
  Filters sensitive data from assigns before recording.

  By default, strips internal LiveView keys and common sensitive fields.
  Configure with:

      config :phoenix_replay,
        sanitizer: MyApp.ReplaySanitizer

  Custom sanitizers must implement `sanitize_assigns/1`.
  """

  @internal_keys [
    :__changed__,
    :flash,
    :live_action,
    :uploads,
    :streams
  ]

  @sensitive_keys [
    :csrf_token,
    :current_password,
    :password,
    :password_confirmation,
    :token,
    :secret
  ]

  @doc """
  Remove internal and sensitive keys from assigns.
  Returns only the data needed for replay.
  """
  def sanitize_assigns(assigns) when is_map(assigns) do
    assigns
    |> Map.drop(@internal_keys ++ @sensitive_keys)
    |> sanitize_values()
  end

  @doc """
  Sanitize only the changed keys (delta).
  """
  def sanitize_delta(changed, assigns) when is_map(changed) and is_map(assigns) do
    changed
    |> Map.keys()
    |> Enum.reject(&(&1 in @internal_keys or &1 in @sensitive_keys))
    |> Map.new(fn key -> {key, Map.get(assigns, key)} end)
    |> sanitize_values()
  end

  defp sanitize_values(map) do
    Map.new(map, fn
      {key, %{__struct__: _} = struct} -> {key, sanitize_struct(struct)}
      {key, value} -> {key, value}
    end)
  end

  defp sanitize_struct(%{__struct__: mod} = struct) do
    if function_exported?(mod, :__schema__, 1) do
      Map.from_struct(struct) |> Map.drop([:__meta__])
    else
      struct
    end
  end
end
