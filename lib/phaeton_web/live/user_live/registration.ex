defmodule PhaetonWeb.UserLive.Registration do
  use PhaetonWeb, :live_view

  alias Phaeton.Accounts
  alias Phaeton.ServerSettings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Create an account
            <:subtitle>
              Already have an account?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-primary hover:underline">
                Log in
              </.link>
            </:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="registration_form"
          phx-change="validate"
          phx-submit="save"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.button class="btn btn-primary w-full mt-2" phx-disable-with="Creating account…">
            Create account <span aria-hidden="true">→</span>
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    unless ServerSettings.registration_enabled?() do
      {:ok, push_navigate(socket, to: ~p"/users/log-in")}
    else
      form = to_form(Accounts.change_user_registration(), as: "user")
      {:ok, assign(socket, form: form)}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      Accounts.change_user_registration(%Phaeton.Accounts.User{}, params)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.register_user(params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account created! You can now log in.")
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        form = changeset |> Map.put(:action, :insert) |> to_form(as: "user")
        {:noreply, assign(socket, form: form)}
    end
  end
end
