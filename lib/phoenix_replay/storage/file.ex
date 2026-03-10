defmodule PhoenixReplay.Storage.File do
  @moduledoc """
  File-based storage backend. Writes one gzip-compressed file per recording.

  ## Options

    * `:path` — directory to store recordings (default: `"priv/replay_recordings"`)
    * `:format` — `:etf` (default) or `:json`
  """

  @behaviour PhoenixReplay.Storage

  alias PhoenixReplay.Storage.Serializer

  defp dir(opts), do: Keyword.get(opts, :path, "priv/replay_recordings")
  defp format(opts), do: Keyword.get(opts, :format, :etf)

  @impl true
  def init(opts) do
    File.mkdir_p!(dir(opts))
    :ok
  end

  @impl true
  def save(recording, opts) do
    with {:ok, data} <- Serializer.encode(recording, format(opts)) do
      path = file_path(recording.id, opts)
      File.write(path, :zlib.gzip(data))
    end
  end

  @impl true
  def get(id, opts) do
    path = file_path(id, opts)

    with {:ok, data} <- File.read(path),
         {:ok, recording} <- Serializer.decode(:zlib.gunzip(data), format(opts)) do
      {:ok, recording}
    else
      _ -> get_legacy(id, opts)
    end
  end

  @impl true
  def list(opts) do
    base = dir(opts)

    case File.ls(base) do
      {:ok, files} ->
        files
        |> Enum.flat_map(fn filename ->
          id = strip_extensions(filename)

          case get(id, opts) do
            {:ok, recording} -> [recording]
            :error -> []
          end
        end)
        |> Enum.sort_by(& &1.connected_at, :desc)

      {:error, _} ->
        []
    end
  end

  @impl true
  def delete(id, opts) do
    path = file_path(id, opts)
    legacy = legacy_path(id, opts)

    File.rm(path)
    File.rm(legacy)
    :ok
  end

  @impl true
  def clear(opts) do
    base = dir(opts)

    case File.ls(base) do
      {:ok, files} ->
        Enum.each(files, fn filename -> File.rm(Path.join(base, filename)) end)
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp file_path(id, opts) do
    basename = Path.basename(id)
    Path.join(dir(opts), basename <> Serializer.extension(format(opts)))
  end

  defp legacy_path(id, opts) do
    basename = Path.basename(id)
    legacy_ext = if format(opts) == :json, do: ".json", else: ".etf"
    Path.join(dir(opts), basename <> legacy_ext)
  end

  defp get_legacy(id, opts) do
    path = legacy_path(id, opts)

    case File.read(path) do
      {:ok, data} ->
        data = maybe_gunzip(data)

        case Serializer.decode(data, format(opts)) do
          {:ok, recording} -> {:ok, recording}
          _ -> :error
        end

      {:error, _} ->
        :error
    end
  end

  defp maybe_gunzip(<<0x1F, 0x8B, _rest::binary>> = data), do: :zlib.gunzip(data)
  defp maybe_gunzip(data), do: data

  defp strip_extensions(filename) do
    filename
    |> String.replace_suffix(".etf.gz", "")
    |> String.replace_suffix(".json.gz", "")
    |> String.replace_suffix(".etf", "")
    |> String.replace_suffix(".json", "")
  end
end
