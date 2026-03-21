defmodule ScientiaCognitaWeb.Router do
  use ScientiaCognitaWeb, :router

  import ScientiaCognitaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ScientiaCognitaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :console do
    plug :require_authenticated_user
    plug :require_console_user
    plug :put_layout, html: {ScientiaCognitaWeb.Layouts, :console}
  end

  ## Google OAuth (user must be logged in to connect Google Photos)

  scope "/auth", ScientiaCognitaWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/google", GoogleAuthController, :request
    get "/google/callback", GoogleAuthController, :callback
  end

  ## Public routes

  scope "/", ScientiaCognitaWeb do
    pipe_through :browser

    live "/", Page.CatalogsIndexLive
    live "/catalogs/:slug", Page.CatalogShowLive
  end

  ## Console — admin/owner only

  scope "/console", ScientiaCognitaWeb.Console do
    pipe_through [:browser, :console]

    live_session :console,
      root_layout: {ScientiaCognitaWeb.Layouts, :console_root},
      layout: {ScientiaCognitaWeb.Layouts, :console},
      on_mount: [{ScientiaCognitaWeb.UserAuth, :require_console_user}] do
      live "/", DashboardLive
      live "/users", UsersLive
      live "/sources", SourcesLive
      live "/sources/:id", SourceShowLive
      live "/catalogs", CatalogsLive
      live "/catalogs/:slug", CatalogShowLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ScientiaCognitaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:scientia_cognita, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ScientiaCognitaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ScientiaCognitaWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", ScientiaCognitaWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", ScientiaCognitaWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
