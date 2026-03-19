alias ScientiaCognita.{Accounts, Repo}
alias ScientiaCognita.Accounts.User

# Create the default owner account if none exists.
# Set OWNER_EMAIL env var to customise (defaults to owner@scientia-cognita.local).
owner_email = System.get_env("OWNER_EMAIL", "owner@scientia-cognita.local")

case Accounts.get_user_by_email(owner_email) do
  nil ->
    %User{}
    |> User.email_changeset(%{email: owner_email})
    |> User.role_changeset(%{role: "owner"})
    |> Repo.insert!()

    IO.puts("Created owner account: #{owner_email}")
    IO.puts("Log in at /users/log-in — a magic link will be sent to #{owner_email}")
    IO.puts("(In dev, check /dev/mailbox for the link)")

  %User{role: "owner"} = user ->
    IO.puts("Owner account already exists: #{user.email}")

  %User{} = user ->
    # Promote to owner if exists but isn't owner yet
    Repo.update!(User.role_changeset(user, %{role: "owner"}))
    IO.puts("Promoted #{user.email} to owner")
end
