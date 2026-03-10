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
  Remove internal and sensitive keys from assigns.
  Returns only the data needed for replay.
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
    %Phoenix.HTML.Form{
      source: compact(form.source),
      params: form.params,
      errors: form.errors,
      name: form.name,
      id: form.id,
      action: form.action,
      data: nil,
      hidden: [],
      impl: nil,
      options: [],
      index: form.index
    }
  end

  defp compact(%{__struct__: Ecto.Changeset} = cs) do
    %{changes: cs.changes, errors: cs.errors, action: cs.action, valid?: cs.valid?}
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
