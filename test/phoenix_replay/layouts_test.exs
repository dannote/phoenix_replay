defmodule PhoenixReplay.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "root layout includes app assets" do
    html = rendered_to_string(PhoenixReplay.Layouts.root(%{inner_content: "content"}))

    assert html =~ "PhoenixReplay"
    assert html =~ "/assets/js/app.js"
    assert html =~ "content"
  end

  test "frame layout disables pointer interaction" do
    html = rendered_to_string(PhoenixReplay.Layouts.frame(%{inner_content: "frame content"}))

    assert html =~ "pointer-events: none"
    assert html =~ "frame content"
  end
end
