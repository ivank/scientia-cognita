defmodule ScientiaCognita.ReleaseTest do
  use ExUnit.Case, async: false

  setup do
    # Start an owner process for database access, as the release module
    # will need to run migrations without async/sandbox interference
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ScientiaCognita.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  test "migrate/0 runs without error" do
    # Runs all pending migrations (none in test env since test setup already migrates)
    assert :ok == ScientiaCognita.Release.migrate()
  end
end
