defmodule PhoenixReplay.Assets do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, :player_js) do
    conn
    |> put_resp_content_type("application/javascript")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, PhoenixReplay.Layouts.player_js())
  end
end
