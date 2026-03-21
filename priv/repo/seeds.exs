alias ScientiaCognita.{Accounts, Repo}
alias ScientiaCognita.Accounts.User

# Create the default owner account if none exists.
# Set OWNER_EMAIL env var to customise (defaults to me@ikerin.com).
owner_email = System.get_env("OWNER_EMAIL", "me@ikerin.com")

case Accounts.get_user_by_email(owner_email) do
  nil ->
    %User{}
    |> User.email_changeset(%{email: owner_email})
    |> User.role_changeset(%{role: "owner"})
    |> User.confirm_changeset()
    |> Repo.insert!()

    IO.puts("Created owner account: #{owner_email}")

  %User{role: "owner"} = user ->
    IO.puts("Owner account already exists: #{user.email}")

  %User{} = user ->
    # Promote to owner if exists but isn't owner yet
    Repo.update!(User.role_changeset(user, %{role: "owner"}))
    IO.puts("Promoted #{user.email} to owner")
end
