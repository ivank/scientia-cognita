defmodule ScientiaCognitaWeb.Emails.MagicLinkEmail do
  @moduledoc """
  Magic link login email.

  Renders with:
    - `email`  — the user's email address
    - `url`    — the one-time login link
  """

  use MjmlEEx,
    mjml_template: "magic_link.mjml.eex",
    layout: ScientiaCognitaWeb.Emails.BaseLayout,
    mode: :compile
end
