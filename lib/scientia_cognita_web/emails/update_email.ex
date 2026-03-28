defmodule ScientiaCognitaWeb.Emails.UpdateEmail do
  @moduledoc """
  Email change confirmation email.
  Sent to the user's current email address to confirm they want to update it.

  Renders with:
    - `email`  — the user's current email address (recipient)
    - `url`    — the email-change confirmation link
  """

  use MjmlEEx,
    mjml_template: "update_email.mjml.eex",
    layout: ScientiaCognitaWeb.Emails.BaseLayout,
    mode: :compile
end
