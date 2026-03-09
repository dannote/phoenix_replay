defmodule Example.Tasks do
  @moduledoc """
  In-memory task store backed by Agent. Good enough for a demo.
  """

  use Agent

  defmodule Task do
    defstruct [:id, :title, :description, :priority, completed: false, inserted_at: nil]
  end

  def start_link(_opts) do
    Agent.start_link(fn -> seed_tasks() end, name: __MODULE__)
  end

  def list_tasks do
    Agent.get(__MODULE__, &Map.values/1) |> Enum.sort_by(& &1.inserted_at, :desc)
  end

  def get_task(id) do
    Agent.get(__MODULE__, &Map.get(&1, id))
  end

  def create_task(attrs) do
    task = %Task{
      id: generate_id(),
      title: attrs["title"] || attrs[:title],
      description: attrs["description"] || attrs[:description],
      priority: attrs["priority"] || attrs[:priority] || "medium",
      completed: false,
      inserted_at: DateTime.utc_now()
    }

    Agent.update(__MODULE__, &Map.put(&1, task.id, task))
    broadcast({:task_created, task})
    {:ok, task}
  end

  def update_task(id, attrs) do
    Agent.get_and_update(__MODULE__, fn tasks ->
      case Map.get(tasks, id) do
        nil ->
          {:error, tasks}

        task ->
          updated =
            task
            |> maybe_update(:title, attrs)
            |> maybe_update(:description, attrs)
            |> maybe_update(:priority, attrs)
            |> maybe_update(:completed, attrs)

          {{:ok, updated}, Map.put(tasks, id, updated)}
      end
    end)
    |> tap(fn
      {:ok, task} -> broadcast({:task_updated, task})
      _ -> :ok
    end)
  end

  def toggle_task(id) do
    case get_task(id) do
      nil -> :error
      task -> update_task(id, %{"completed" => !task.completed})
    end
  end

  def delete_task(id) do
    Agent.get_and_update(__MODULE__, fn tasks ->
      case Map.pop(tasks, id) do
        {nil, _} -> {:error, tasks}
        {task, rest} -> {{:ok, task}, rest}
      end
    end)
    |> tap(fn
      {:ok, task} -> broadcast({:task_deleted, task})
      _ -> :ok
    end)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Example.PubSub, "tasks")
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Example.PubSub, "tasks", message)
  end

  defp maybe_update(struct, key, attrs) do
    str_key = to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.put(struct, key, attrs[key])
      Map.has_key?(attrs, str_key) -> Map.put(struct, key, attrs[str_key])
      true -> struct
    end
  end

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  end

  defp seed_tasks do
    tasks = [
      %Task{
        id: generate_id(),
        title: "Review PR #42",
        description: "Check the new authentication flow",
        priority: "high",
        inserted_at: DateTime.utc_now()
      },
      %Task{
        id: generate_id(),
        title: "Update dependencies",
        description: "Run mix deps.update --all",
        priority: "low",
        completed: true,
        inserted_at: DateTime.add(DateTime.utc_now(), -3600)
      },
      %Task{
        id: generate_id(),
        title: "Write documentation",
        description: "Add module docs for the Tasks context",
        priority: "medium",
        inserted_at: DateTime.add(DateTime.utc_now(), -7200)
      }
    ]

    Map.new(tasks, &{&1.id, &1})
  end
end
