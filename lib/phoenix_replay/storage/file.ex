defmodule PhoenixReplay.Storage.File do
  @moduledoc """
  File-based storage backend. Writes one file per recording.

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
      File.write(path, data)
    end
  end

  @impl true
  def get(id, opts) do
    path = file_path(id, opts)

    case File.read(path) do
      {:ok, data} ->
        case Serializer.decode(data, format(opts)) do
          {:ok, recording} -> {:ok, recording}
          {:error, _} -> :error
        end

      {:error, _} ->
        :error
    end
  end

  @impl true
  def list(opts) do
    ext = Serializer.extension(format(opts))
    base = dir(opts)

    case File.ls(base) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ext))
        |> Enum.flat_map(fn filename ->
          id = String.trim_trailing(filename, ext)

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

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @impl true
  def clear(opts) do
    ext = Serializer.extension(format(opts))
    base = dir(opts)

    case File.ls(base) do
      {:ok, files} ->
        Enum.each(files, fn filename ->
          if String.ends_with?(filename, ext) do
            File.rm(Path.join(base, filename))
          end
        end)

        :ok

      {:error, _} ->
        :ok
    end
  end

  defp file_path(id, opts) do
    Path.join(dir(opts), id <> Serializer.extension(format(opts)))
  end
end
