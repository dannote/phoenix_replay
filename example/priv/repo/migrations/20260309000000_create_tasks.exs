defmodule Example.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :priority, :string, default: "medium"
      add :completed, :boolean, default: false

      timestamps(type: :utc_datetime)
    end
  end
end
