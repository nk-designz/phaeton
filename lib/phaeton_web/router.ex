defmodule PhaetonWeb.Router do
  use PhaetonWeb, :router
  import PhaetonWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhaetonWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug PhaetonWeb.Plugs.CheckSetup
  end

  pipeline :redirect_if_authenticated do
    plug :redirect_if_user_is_authenticated
  end

  pipeline :require_authenticated do
    plug :require_authenticated_user
  end

  pipeline :api do
    plug :accepts, ["json", "ld+json"]
    plug PhaetonWeb.Plugs.NGSILD
    plug PhaetonWeb.Plugs.APIAuth
  end

  ## Setup route (only accessible when no users exist)
  scope "/", PhaetonWeb do
    pipe_through :browser

    live "/setup", SetupLive
  end

  ## Authentication routes
  scope "/", PhaetonWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PhaetonWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/register", UserLive.Registration, :new
    end

    post "/users/log-in", UserSessionController, :create
  end

  scope "/", PhaetonWeb do
    pipe_through [:browser, :require_authenticated]

    live_session :require_authenticated_user,
      on_mount: [{PhaetonWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit

      live "/", DashboardLive
      live "/entities", EntityLive.Index, :index
      live "/entities/new", EntityLive.Index, :new
      live "/entities/:id", EntityLive.Show, :show
      live "/entities/:id/edit", EntityLive.Show, :edit
      live "/entities/:id/attrs/new", EntityLive.Show, :new_attr
      live "/map", MapLive
      live "/charts", ChartLive
      live "/subscriptions", SubscriptionLive
      live "/types", TypeLive
    end
  end

  scope "/", PhaetonWeb do
    pipe_through :browser

    delete "/users/log-out", UserSessionController, :delete
    post "/users/update-password", UserSessionController, :update_password
    post "/users/active-tenant", UserTenantController, :update

    live_session :admin,
      on_mount: [{PhaetonWeb.UserAuth, :require_admin}] do
      live "/graph", GraphLive
      live "/cluster", ClusterLive
      live "/sparql", SparqlLive
      live "/admin/tenants", Admin.TenantLive, :index
      live "/admin/tenants/new", Admin.TenantLive, :new
      live "/admin/tenants/:id/edit", Admin.TenantLive, :edit
      live "/admin/users", Admin.UserLive, :index
      live "/admin/users/new", Admin.UserLive, :new
      live "/admin/users/:id/edit", Admin.UserLive, :edit
      live "/admin/users/:id/tokens", Admin.UserLive, :tokens
      live "/admin/groups", Admin.GroupLive, :index
      live "/admin/groups/new", Admin.GroupLive, :new
      live "/admin/groups/:id/edit", Admin.GroupLive, :edit
      live "/admin/groups/:id/members", Admin.GroupLive, :members
      live "/admin/settings", Admin.SettingsLive
    end
  end

  # NGSI-LD API v1
  scope "/ngsi-ld/v1", PhaetonWeb.API do
    pipe_through :api

    # Entity operations
    resources "/entities", EntityController, only: [:create, :index], param: "entity_id"
    get "/entities/:entity_id", EntityController, :show
    delete "/entities/:entity_id", EntityController, :delete
    patch "/entities/:entity_id", EntityController, :merge
    put "/entities/:entity_id", EntityController, :replace

    # Entity attribute operations
    post "/entities/:entity_id/attrs", EntityController, :append_attrs
    patch "/entities/:entity_id/attrs", EntityController, :update_attrs
    patch "/entities/:entity_id/attrs/:attr_id", EntityController, :update_attr
    delete "/entities/:entity_id/attrs/:attr_id", EntityController, :delete_attr
    put "/entities/:entity_id/attrs/:attr_id", EntityController, :replace_attr

    # Batch entity operations
    post "/entityOperations/create", BatchController, :create
    post "/entityOperations/upsert", BatchController, :upsert
    post "/entityOperations/update", BatchController, :update
    post "/entityOperations/delete", BatchController, :delete
    post "/entityOperations/merge", BatchController, :merge
    post "/entityOperations/query", BatchController, :query

    # Subscriptions
    resources "/subscriptions", SubscriptionController,
      only: [:create, :index],
      param: "subscription_id"

    get "/subscriptions/:subscription_id", SubscriptionController, :show
    patch "/subscriptions/:subscription_id", SubscriptionController, :update
    delete "/subscriptions/:subscription_id", SubscriptionController, :delete

    # Types / Discovery
    get "/types", TypeController, :index
    get "/types/:type", TypeController, :show

    # Attributes / Discovery
    get "/attributes", AttributeController, :index
    get "/attributes/:attr_id", AttributeController, :show

    # JSON-LD Context management
    resources "/jsonldContexts", ContextController,
      only: [:create, :index],
      param: "context_id"

    get "/jsonldContexts/:context_id", ContextController, :show
    delete "/jsonldContexts/:context_id", ContextController, :delete

    # Temporal entity operations
    post "/temporal/entities", TemporalController, :create
    get "/temporal/entities", TemporalController, :index
    get "/temporal/entities/:entity_id", TemporalController, :show
    delete "/temporal/entities/:entity_id", TemporalController, :delete
    post "/temporal/entities/:entity_id/attrs", TemporalController, :append_attrs
    delete "/temporal/entities/:entity_id/attrs/:attr_id", TemporalController, :delete_attr

    patch "/temporal/entities/:entity_id/attrs/:attr_id/:instance_id",
          TemporalController,
          :update_attr_instance

    delete "/temporal/entities/:entity_id/attrs/:attr_id/:instance_id",
           TemporalController,
           :delete_attr_instance

    post "/temporal/entityOperations/query", TemporalController, :query_batch

    # Context Source Registrations
    post "/csourceRegistrations", CSourceRegistrationController, :create
    get "/csourceRegistrations", CSourceRegistrationController, :index
    get "/csourceRegistrations/:registration_id", CSourceRegistrationController, :show
    patch "/csourceRegistrations/:registration_id", CSourceRegistrationController, :update
    delete "/csourceRegistrations/:registration_id", CSourceRegistrationController, :delete

    # Context Source Subscriptions
    post "/csourceSubscriptions", CSourceSubscriptionController, :create
    get "/csourceSubscriptions", CSourceSubscriptionController, :index
    get "/csourceSubscriptions/:subscription_id", CSourceSubscriptionController, :show
    patch "/csourceSubscriptions/:subscription_id", CSourceSubscriptionController, :update
    delete "/csourceSubscriptions/:subscription_id", CSourceSubscriptionController, :delete

    # Entity Map
    get "/entityMap/:entity_map_id", EntityMapController, :show
    patch "/entityMap/:entity_map_id", EntityMapController, :update
    delete "/entityMap/:entity_map_id", EntityMapController, :delete

    # SPARQL Query
    post "/sparql", SparqlController, :query

    # System Info
    get "/info/sourceIdentity", InfoController, :source_identity
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:phaeton, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PhaetonWeb.Telemetry
    end
  end
end
