defmodule ScientiaCognita.Repo do
  use Ecto.Repo,
    otp_app: :scientia_cognita,
    adapter: Ecto.Adapters.SQLite3
end
