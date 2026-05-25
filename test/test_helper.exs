Application.put_env(:phoenix, :json_library, Jason)
{:ok, _} = PhoenixReplay.TestEndpoint.start_link()

ExUnit.after_suite(fn _ ->
  PhoenixReplay.Store.clear_all()
end)

defmodule PhoenixReplay.TestSupport do
  import ExUnit.Assertions

  def assert_eventually(fun, timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    assert_eventually(fun, deadline, nil)
  end

  defp assert_eventually(fun, deadline, last_result) do
    case fun.() do
      {:ok, value} ->
        value

      other ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("condition did not become true, last result: #{inspect(other || last_result)}")
        else
          Process.sleep(10)
          assert_eventually(fun, deadline, other)
        end
    end
  end
end

ExUnit.start()
