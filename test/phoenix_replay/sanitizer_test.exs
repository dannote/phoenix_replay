defmodule PhoenixReplay.SanitizerTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Sanitizer

  test "sanitize_assigns strips internal keys but keeps live_action" do
    assigns = %{
      __changed__: %{count: true},
      flash: %{},
      live_action: :index,
      count: 42,
      user: "Dan"
    }

    result = Sanitizer.sanitize_assigns(assigns)

    refute Map.has_key?(result, :__changed__)
    refute Map.has_key?(result, :flash)
    assert result.live_action == :index
    assert result.count == 42
    assert result.user == "Dan"
  end

  test "sanitize_assigns strips sensitive keys" do
    assigns = %{
      __changed__: %{},
      password: "secret123",
      csrf_token: "abc",
      token: "bearer xyz",
      name: "Dan"
    }

    result = Sanitizer.sanitize_assigns(assigns)

    refute Map.has_key?(result, :password)
    refute Map.has_key?(result, :csrf_token)
    refute Map.has_key?(result, :token)
    assert result.name == "Dan"
  end

  test "sanitize_delta returns only changed non-internal keys" do
    changed = %{count: true, __changed__: true, flash: true, live_action: true}

    assigns = %{
      count: 5,
      __changed__: %{count: true},
      flash: %{},
      live_action: :edit,
      name: "Dan"
    }

    result = Sanitizer.sanitize_delta(changed, assigns)

    assert result == %{count: 5, live_action: :edit}
  end

  test "sanitize_delta returns empty map when only internal keys changed" do
    changed = %{__changed__: true, flash: true}
    assigns = %{__changed__: %{}, flash: %{}, count: 5}

    result = Sanitizer.sanitize_delta(changed, assigns)

    assert result == %{}
  end
end
