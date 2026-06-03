defmodule PhaetonWeb.Admin.SettingsLive do
  use PhaetonWeb, :live_view

  alias Phaeton.ServerSettings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Server Settings")
     |> assign(:registration_enabled, ServerSettings.registration_enabled?())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_tab={:admin_settings}>
      <div class="max-w-2xl mx-auto space-y-6">
        <.header>
          Server Settings
          <:subtitle>Global configuration for this Phaeton instance.</:subtitle>
        </.header>

        <div class="card bg-base-100 border-2 border-nb shadow-nb">
          <div class="card-body gap-4">
            <h2 class="card-title text-base">Authentication</h2>

            <div class="flex items-center justify-between gap-4">
              <div>
                <div class="font-semibold">Public registration</div>
                <div class="text-sm opacity-60">
                  Allow anyone to create an account at <code>/users/register</code>.
                  When disabled, only admins can create new users.
                </div>
              </div>
              <input
                type="checkbox"
                class="toggle toggle-primary"
                checked={@registration_enabled}
                phx-click="toggle_registration"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("toggle_registration", _params, socket) do
    new_value = !socket.assigns.registration_enabled

    case ServerSettings.set_registration_enabled(new_value) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:registration_enabled, new_value)
         |> put_flash(
           :info,
           if(new_value, do: "Registration enabled.", else: "Registration disabled.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update setting.")}
    end
  end
end
