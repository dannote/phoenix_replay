defmodule Example.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :priority, :string, default: "medium"
    field :completed, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :priority, :completed])
    |> validate_required([:title])
  end
end
