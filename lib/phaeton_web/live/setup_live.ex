defmodule PhaetonWeb.SetupLive do
  use PhaetonWeb, :live_view

  alias Phaeton.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen nb-page-bg flex items-center justify-center p-4">
      <div class="w-full max-w-md">
        <%!-- Logo / branding --%>
        <div class="text-center mb-8">
          <div class="inline-flex items-center justify-center w-14 h-14 rounded-[10px] bg-gradient-nb border-2 border-nb shadow-nb mb-4">
            <.icon name="hero-cube-transparent" class="size-8 text-white" />
          </div>
          <h1 class="text-2xl font-bold tracking-tight text-gradient-nb">Phaeton</h1>
          <p class="text-sm opacity-50 mt-1 uppercase tracking-widest font-semibold">
            NGSI-LD Broker
          </p>
        </div>

        <%!-- Setup card --%>
        <div class="bg-base-200 border-2 border-nb shadow-nb rounded-[10px] p-6">
          <div class="mb-6">
            <h2 class="text-lg font-bold">Initial Setup</h2>
            <p class="text-sm opacity-60 mt-1">
              Create your admin account to get started.
            </p>
          </div>

          <.flash kind={:info} flash={@flash} />
          <.flash kind={:error} flash={@flash} />

          <.form for={@form} id="setup-form" phx-change="validate" phx-submit="save">
            <%!-- Tenant --%>
            <div class="mb-4">
              <.input
                field={@form[:tenant]}
                type="text"
                label="Tenant Name"
                placeholder="my-organisation"
                autocomplete="off"
                phx-mounted={JS.focus()}
              />
              <p class="text-xs opacity-40 mt-1">
                Lowercase letters, numbers, hyphens and underscores only.
              </p>
            </div>

            <%!-- Email --%>
            <div class="mb-4">
              <.input
                field={@form[:email]}
                type="email"
                label="Admin Email"
                placeholder="admin@example.com"
                autocomplete="username"
                spellcheck="false"
              />
            </div>

            <%!-- Password --%>
            <div class="mb-4">
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                placeholder="at least 12 characters"
                autocomplete="new-password"
              />
            </div>

            <%!-- Confirm password --%>
            <div class="mb-6">
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm Password"
                autocomplete="new-password"
              />
            </div>

            <.button
              phx-disable-with="Setting up…"
              class="btn btn-primary w-full"
            >
              Create Admin Account <.icon name="hero-arrow-right" class="size-4 ml-1" />
            </.button>
          </.form>
        </div>

        <p class="text-center text-xs opacity-30 mt-6">
          This page is only accessible when no users exist.
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.needs_setup?() do
      {:ok, assign(socket, form: to_form(Accounts.change_admin_setup()))}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_admin_setup(%Phaeton.Accounts.User{}, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.register_admin(params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Admin account created. Please log in.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :insert))}
    end
  end
end
