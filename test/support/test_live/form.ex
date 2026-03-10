defmodule PhoenixReplay.TestLive.Form do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, name: "", submitted: false)}
  end

  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, name: name)}
  end

  def handle_event("submit", %{"name" => name}, socket) do
    {:noreply, assign(socket, name: name, submitted: true)}
  end

  def render(assigns) do
    ~H"""
    <form phx-change="validate" phx-submit="submit">
      <input type="text" name="name" value={@name} />
      <button type="submit">Submit</button>
      <span :if={@submitted} id="done">Submitted: {@name}</span>
    </form>
    """
  end
end
