defmodule PhoenixReplay.Assets do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, :player_js) do
    conn
    |> put_resp_content_type("application/javascript")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, player_js())
  end

  defp player_js do
    :code.priv_dir(:phoenix_replay)
    |> Path.join("static/phoenix_replay/player.js")
    |> File.read!()
  rescue
    _ in [ArgumentError, ErlangError, File.Error] ->
      Path.join([File.cwd!(), "priv", "static", "phoenix_replay", "player.js"])
      |> File.read!()
  end
end
