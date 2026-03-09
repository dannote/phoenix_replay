defmodule PhoenixReplay.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixReplay.Store
    ]

    opts = [strategy: :one_for_one, name: PhoenixReplay.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
