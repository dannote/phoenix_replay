alias Example.Repo
alias Example.Tasks.Task

now = DateTime.utc_now() |> DateTime.truncate(:second)

Repo.insert!(%Task{
  title: "Review PR #42",
  description: "Check the new authentication flow",
  priority: "high",
  inserted_at: now,
  updated_at: now
})

Repo.insert!(%Task{
  title: "Update dependencies",
  description: "Run mix deps.update --all",
  priority: "low",
  completed: true,
  inserted_at: DateTime.add(now, -3600),
  updated_at: DateTime.add(now, -3600)
})

Repo.insert!(%Task{
  title: "Write documentation",
  description: "Add module docs for the Tasks context",
  priority: "medium",
  inserted_at: DateTime.add(now, -7200),
  updated_at: DateTime.add(now, -7200)
})
