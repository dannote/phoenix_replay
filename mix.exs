defmodule PhoenixReplay.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dannote/phoenix_replay"

  def project do
    [
      app: :phoenix_replay,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "PhoenixReplay",
      description: "Session recording and replay for Phoenix LiveView"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PhoenixReplay.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:jason, "~> 1.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "PhoenixReplay",
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end
end
