defmodule ScientiaCognitaWeb.Dev.EmailPreviewController do
  @moduledoc """
  Development-only controller for previewing email templates.
  Available at /dev/emails (index) and /dev/emails/:template (preview).
  """

  use ScientiaCognitaWeb, :controller

  alias ScientiaCognitaWeb.Emails

  @sample_url "https://sc.ikerin.com/users/log-in/SFMyNTY.sample_token_for_preview"
  @sample_email "preview@example.com"

  defp templates do
    [
      %{
        id: "magic_link",
        name: "Magic Link Login",
        subject: "Your login link — Scientia Cognita",
        description: "Sent when an existing user requests a login link."
      },
      %{
        id: "confirm_email",
        name: "Confirm Email (New User)",
        subject: "Confirm your email address — Scientia Cognita",
        description: "Sent to new users who haven't confirmed their account yet."
      },
      %{
        id: "update_email",
        name: "Update Email",
        subject: "Confirm your email change — Scientia Cognita",
        description: "Sent when a user requests to change their email address."
      }
    ]
  end

  defp render_template("magic_link") do
    Emails.MagicLinkEmail.render(email: @sample_email, url: @sample_url)
  end

  defp render_template("confirm_email") do
    Emails.ConfirmEmail.render(email: @sample_email, url: @sample_url)
  end

  defp render_template("update_email") do
    Emails.UpdateEmail.render(
      email: @sample_email,
      url: "https://sc.ikerin.com/users/settings/confirm-email/SFMyNTY.sample_token"
    )
  end

  defp render_template(_), do: nil

  def index(conn, _params) do
    render(conn, :index, templates: templates())
  end

  def show(conn, %{"template" => template_id}) do
    case {Enum.find(templates(), &(&1.id == template_id)), render_template(template_id)} do
      {nil, _} ->
        valid = Enum.map_join(templates(), ", ", & &1.id)

        conn
        |> put_status(:not_found)
        |> text("Template '#{template_id}' not found. Valid templates: #{valid}")

      {template, html} ->
        render(conn, :show, template: template, html: html, text: Premailex.to_text(html))
    end
  end

  def raw(conn, %{"template" => template_id}) do
    case render_template(template_id) do
      nil ->
        conn |> put_status(:not_found) |> text("Template not found.")

      html ->
        conn |> put_resp_content_type("text/html") |> send_resp(200, html)
    end
  end
end
