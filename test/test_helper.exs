Application.put_env(:phoenix, :json_library, Jason)
{:ok, _} = PhoenixReplay.TestEndpoint.start_link()
ExUnit.start()
