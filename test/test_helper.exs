Application.put_env(:phoenix, :json_library, Jason)
{:ok, _} = PhoenixReplay.TestEndpoint.start_link()

ExUnit.after_suite(fn _ ->
  PhoenixReplay.Store.clear_all()
end)

ExUnit.start()
