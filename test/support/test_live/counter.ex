defmodule PhoenixReplay.TestLive.Counter do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, count: socket.assigns.count + 1)}
  end

  def handle_event("dec", _params, socket) do
    {:noreply, assign(socket, count: socket.assigns.count - 1)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <span id="count"><%= @count %></span>
      <button phx-click="inc">+</button>
      <button phx-click="dec">-</button>
    </div>
    """
  end
end
