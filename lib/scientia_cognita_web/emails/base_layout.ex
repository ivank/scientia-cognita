defmodule ScientiaCognitaWeb.Emails.BaseLayout do
  @moduledoc """
  The shared Scientia Cognita email layout.

  All transactional emails use this layout for consistent branding:
  a dark header with logo and app name, a white content area, and a dark footer.

  MJML is compiled to HTML at Elixir compile time (via the Rust NIF).
  The resulting HTML template is evaluated with EEx at render time.
  When this file or base_layout.mjml.eex changes, mix compile recompiles it.
  """

  use MjmlEEx.Layout, mjml_layout: "base_layout.mjml.eex"
end
