defmodule PhoenixReplay.Sanitizer do
  @moduledoc """
  Filters sensitive data from assigns before recording.

  By default, strips internal LiveView keys and common sensitive fields,
  compacts Ecto structs and Phoenix form structs for minimal storage.

  Configure with:

      config :phoenix_replay,
        sanitizer: MyApp.ReplaySanitizer

  Custom sanitizers must implement `sanitize_assigns/1` and `sanitize_delta/2`.
  """

  @internal_keys [
    :__changed__,
    :flash,
    :uploads,
    :streams,
    :_replay_id,
    :_replay_t0
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
  Remove internal and sensitive keys from assigns, compact structs.

  Drops internal LiveView keys and sensitive fields, then compacts
  `Phoenix.HTML.Form`, `Ecto.Changeset`, and Ecto schema structs
  to remove runtime-only data (changeset types, validations, schema metadata).
  """
  def sanitize_assigns(assigns) when is_map(assigns) do
    assigns
    |> Map.drop(@internal_keys ++ @sensitive_keys)
    |> Map.new(fn {k, v} -> {k, compact(v)} end)
  end

  @doc """
  Sanitize only the changed keys (delta).
  """
  def sanitize_delta(changed, assigns) when is_map(changed) and is_map(assigns) do
    changed
    |> Map.keys()
    |> Enum.reject(&(&1 in @internal_keys or &1 in @sensitive_keys))
    |> Map.new(fn key -> {key, compact(Map.get(assigns, key))} end)
  end

  defp compact(%{__struct__: Phoenix.HTML.Form} = form) do
    %{form | source: compact(form.source), data: compact(form.data), options: []}
  end

  defp compact(%{__struct__: Ecto.Changeset} = cs) do
    %{
      cs
      | data: compact(cs.data),
        changes: compact(cs.changes),
        types: nil,
        validations: [],
        prepare: [],
        repo: nil,
        repo_opts: []
    }
  end

  defp compact(%{__struct__: mod} = struct) do
    if function_exported?(mod, :__schema__, 1) do
      struct |> Map.from_struct() |> Map.drop([:__meta__])
    else
      struct
    end
  end

  defp compact(list) when is_list(list), do: Enum.map(list, &compact/1)

  defp compact(value), do: value
end
