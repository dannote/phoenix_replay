defmodule PhoenixReplay.AssetsTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  import Plug.Conn, only: [get_resp_header: 2]

  @endpoint PhoenixReplay.TestEndpoint

  test "serves replay player JavaScript" do
    conn = get(build_conn(), "/replay/player.js")

    assert response(conn, 200) =~ "phx:init"
    assert get_resp_header(conn, "content-type") == ["application/javascript; charset=utf-8"]
  end
end
