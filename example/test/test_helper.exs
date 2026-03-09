Ecto.Adapters.SQL.Sandbox.mode(Example.Repo, :manual)

{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
Application.put_env(:phoenix_test, :base_url, ExampleWeb.Endpoint.url())

ExUnit.start()
