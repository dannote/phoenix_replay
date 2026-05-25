defmodule PhoenixReplay.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "root layout includes replay player script" do
    html = rendered_to_string(PhoenixReplay.Layouts.root(%{inner_content: "content"}))

    assert html =~ "PhoenixReplay"
    assert html =~ "phx:init"
    assert html =~ "content"
  end

  test "frame layout disables pointer interaction" do
    html = rendered_to_string(PhoenixReplay.Layouts.frame(%{inner_content: "frame content"}))

    assert html =~ "pointer-events: none"
    assert html =~ "frame content"
  end
end
