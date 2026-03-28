defmodule ScientiaCognitaWeb.Emails.ConfirmEmail do
  @moduledoc """
  Account confirmation email sent to new users.

  Renders with:
    - `email`  — the user's email address
    - `url`    — the confirmation link
  """

  use MjmlEEx,
    mjml_template: "confirm_email.mjml.eex",
    layout: ScientiaCognitaWeb.Emails.BaseLayout,
    mode: :compile
end
