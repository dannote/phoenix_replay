defmodule PhoenixReplay.TestEndpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_replay

  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Session,
    store: :cookie,
    key: "_replay_test",
    signing_salt: "test_salt"
  )

  plug(:put_secret_key_base)

  defp put_secret_key_base(conn, _) do
    put_in(
      conn.secret_key_base,
      String.duplicate("a", 64)
    )
  end

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(PhoenixReplay.TestRouter)
end
