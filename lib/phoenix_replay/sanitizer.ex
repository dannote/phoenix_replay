defmodule PhoenixReplay.Sanitizer do
  @moduledoc """
  Filters sensitive data from assigns before recording.

  By default, strips internal LiveView keys and common sensitive fields,
  compacts Ecto structs and Phoenix form structs for minimal storage.

  Configure with:

      config :phoenix_replay,
        sanitizer: MyApp.ReplaySanitizer

  Custom sanitizers must implement `sanitize_assigns/1` and `sanitize_delta/2`.
  They may also implement `sanitize_params/1`; otherwise params are sanitized
  with `sanitize_assigns/1`.
  """

  @callback sanitize_assigns(map()) :: map()
  @callback sanitize_delta(map(), map()) :: map()
  @callback sanitize_params(map()) :: map()
  @optional_callbacks sanitize_params: 1

  @internal_keys [
    :__changed__,
    :flash,
    :uploads,
    :streams,
    :_replay_id,
    :_replay_t0
  ]

  @sensitive_keys [
    :_csrf_token,
    :csrf_token,
    :current_password,
    :password,
    :password_confirmation,
    :user_token,
    :token,
    :secret
  ]
  @sensitive_key_names Enum.map(@sensitive_keys, &(&1 |> Atom.to_string() |> String.downcase()))

  @doc """
  Remove internal and sensitive keys from assigns, compact structs.

  Drops internal LiveView keys and sensitive fields, then compacts
  `Phoenix.HTML.Form`, `Ecto.Changeset`, and Ecto schema structs
  to remove runtime-only data (changeset types, validations, schema metadata).
  """
  @spec sanitize_assigns(map()) :: map()
  def sanitize_assigns(assigns) when is_map(assigns) do
    sanitize_map(assigns, drop_internal?: true)
  end

  @doc "Sanitize params or session data before recording."
  @spec sanitize_params(map()) :: map()
  def sanitize_params(params) when is_map(params) do
    sanitize_map(params, drop_internal?: false)
  end

  @doc """
  Sanitize only the changed keys (delta).
  """
  @spec sanitize_delta(map(), map()) :: map()
  def sanitize_delta(changed, assigns) when is_map(changed) and is_map(assigns) do
    changed
    |> Map.keys()
    |> Enum.reject(&drop_key?(&1, drop_internal?: true))
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
      struct
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> sanitize_map(drop_internal?: false)
    else
      struct
    end
  end

  defp compact(map) when is_map(map), do: sanitize_map(map, drop_internal?: false)
  defp compact(list) when is_list(list), do: Enum.map(list, &compact/1)

  defp compact(value), do: value

  defp sanitize_map(map, opts) do
    map
    |> Enum.reject(fn {key, _value} -> drop_key?(key, opts) end)
    |> Map.new(fn {key, value} -> {key, compact(value)} end)
  end

  defp drop_key?(key, opts) do
    key_name = key |> key_name() |> String.downcase()
    sensitive? = key_name in @sensitive_key_names
    internal? = Keyword.get(opts, :drop_internal?, false) and key in @internal_keys

    sensitive? or internal?
  end

  defp key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp key_name(key) when is_binary(key), do: key
  defp key_name(key), do: inspect(key)
end
