ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ScientiaCognita.Repo, :manual)

# Define Mox mocks — must happen before tests load
Code.require_file("support/mocks.ex", __DIR__)
