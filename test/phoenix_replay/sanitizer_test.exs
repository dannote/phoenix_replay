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

  test "sanitize_assigns strips replay internal keys" do
    assigns = %{
      _replay_id: "abc123",
      _replay_t0: 1_234_567_890,
      count: 5
    }

    result = Sanitizer.sanitize_assigns(assigns)

    refute Map.has_key?(result, :_replay_id)
    refute Map.has_key?(result, :_replay_t0)
    assert result.count == 5
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

  test "compact strips Phoenix.HTML.Form internals" do
    form = %Phoenix.HTML.Form{
      source: %{some: :changeset_data},
      params: %{"title" => "Hello"},
      errors: [title: {"required", []}],
      name: "task",
      id: "task",
      action: :validate,
      data: %{title: nil, id: 1},
      hidden: [_method: "put"],
      impl: Phoenix.HTML.FormData.Map,
      options: [method: "post"],
      index: nil
    }

    assigns = %{form: form, count: 1}
    result = Sanitizer.sanitize_assigns(assigns)

    compacted = result.form
    assert compacted.params == %{"title" => "Hello"}
    assert compacted.errors == [title: {"required", []}]
    assert compacted.name == "task"
    assert compacted.id == "task"
    assert compacted.action == :validate
    assert compacted.data == nil
    assert compacted.hidden == []
    assert compacted.impl == nil
    assert compacted.options == []
  end

  defmodule FakeSchema do
    def __schema__(:source), do: "items"
  end

  test "compact handles lists of structs" do
    assigns = %{
      items: [
        %{__struct__: FakeSchema, __meta__: :loaded, id: 1, name: "a"},
        %{__struct__: FakeSchema, __meta__: :loaded, id: 2, name: "b"}
      ]
    }

    result = Sanitizer.sanitize_assigns(assigns)

    assert length(result.items) == 2
    first = hd(result.items)
    refute Map.has_key?(first, :__meta__)
    assert first.id == 1
  end
end
