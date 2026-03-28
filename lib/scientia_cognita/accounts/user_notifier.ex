defmodule ScientiaCognita.Accounts.UserNotifier do
  import Swoosh.Email

  alias ScientiaCognita.Mailer
  alias ScientiaCognita.Accounts.User
  alias ScientiaCognitaWeb.Emails

  @from_address {"Scientia Cognita", "no-reply@sc.ikerin.com"}

  # Builds and delivers an HTML + plain-text email.
  # `html` is the rendered HTML string; plain text is derived automatically.
  defp deliver(recipient, subject, html) do
    text = Premailex.to_text(html)

    email =
      new()
      |> to(recipient)
      |> from(@from_address)
      |> subject(subject)
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    html = Emails.UpdateEmail.render(email: user.email, url: url)
    deliver(user.email, "Confirm your email change", html)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  New (unconfirmed) users receive a confirmation email; returning users a login link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    html = Emails.MagicLinkEmail.render(email: user.email, url: url)
    deliver(user.email, "Your login link — Scientia Cognita", html)
  end

  defp deliver_confirmation_instructions(user, url) do
    html = Emails.ConfirmEmail.render(email: user.email, url: url)
    deliver(user.email, "Confirm your email address — Scientia Cognita", html)
  end
end
