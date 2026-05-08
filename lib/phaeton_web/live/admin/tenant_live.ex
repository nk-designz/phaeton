defmodule PhaetonWeb.Admin.TenantLive do
  use PhaetonWeb, :live_view

  alias Phaeton.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tenants")
     |> assign(:form, nil)
     |> load_tenants()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, tenant: nil, form: nil)
  end

  defp apply_action(socket, :new, _params) do
    tenant = %Accounts.Tenant{}
    assign(socket, tenant: tenant, form: to_form(Accounts.change_tenant(tenant)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    tenant = Accounts.get_tenant!(id)
    assign(socket, tenant: tenant, form: to_form(Accounts.change_tenant(tenant)))
  end

  @impl true
  def handle_event("validate", %{"tenant" => params}, socket) do
    changeset = Accounts.change_tenant(socket.assigns.tenant, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"tenant" => params}, socket) do
    save_tenant(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tenant = Accounts.get_tenant!(id)

    case Accounts.delete_tenant(tenant) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tenant \"#{tenant.name}\" deleted.")
         |> load_tenants()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete tenant.")}
    end
  end

  defp save_tenant(socket, :new, params) do
    case Accounts.create_tenant(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tenant created successfully.")
         |> push_patch(to: ~p"/admin/tenants")
         |> load_tenants()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_tenant(socket, :edit, params) do
    case Accounts.update_tenant(socket.assigns.tenant, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tenant updated.")
         |> push_patch(to: ~p"/admin/tenants")
         |> load_tenants()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp load_tenants(socket) do
    tenants = Accounts.list_tenants()
    counts = Map.new(tenants, fn t -> {t.name, Accounts.tenant_user_count(t.name)} end)
    assign(socket, tenants: tenants, user_counts: counts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:admin_tenants} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight heading-gradient">Tenants</h1>
            <p class="text-sm opacity-60 mt-1">Manage logical namespaces for data isolation</p>
          </div>
          <.link patch={~p"/admin/tenants/new"}>
            <button class="btn btn-sm border-2 border-nb shadow-nb-sm bg-gradient-nb text-white font-bold hover:opacity-90 transition-opacity">
              <.icon name="hero-plus" class="size-4" /> New Tenant
            </button>
          </.link>
        </div>

        <div class="card bg-base-200 border-2 border-nb shadow-nb rounded-[10px] overflow-hidden">
          <%= if @tenants == [] do %>
            <div class="p-12 text-center opacity-50">
              <.icon name="hero-building-office" class="size-10 mx-auto mb-3" />
              <p class="font-semibold">No tenants yet</p>
              <p class="text-sm mt-1">Create a tenant to start organizing your data</p>
            </div>
          <% else %>
            <table class="table table-sm w-full">
              <thead>
                <tr class="border-b-2 border-nb text-[11px] uppercase tracking-widest opacity-50 font-bold">
                  <th class="px-4 py-3">Name</th>
                  <th class="px-4 py-3">Description</th>
                  <th class="px-4 py-3">Users</th>
                  <th class="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for tenant <- @tenants do %>
                  <tr class="border-b border-base-300 hover:bg-base-300/40 transition-colors">
                    <td class="px-4 py-3">
                      <span class="inline-flex items-center gap-1.5 px-2 py-1 rounded text-[11px] font-bold bg-nb-accent/20 text-nb-accent border border-nb-accent/40">
                        <.icon name="hero-building-office" class="size-3" />
                        {tenant.name}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-sm opacity-70">{tenant.description || "—"}</td>
                    <td class="px-4 py-3">
                      <span class="badge badge-sm badge-ghost font-mono">
                        {@user_counts[tenant.name] || 0}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <div class="flex items-center justify-end gap-2">
                        <.link patch={~p"/admin/tenants/#{tenant.id}/edit"}>
                          <button class="btn btn-xs btn-ghost border border-base-300 hover:border-nb">
                            <.icon name="hero-pencil-square" class="size-3.5" /> Edit
                          </button>
                        </.link>
                        <button
                          class="btn btn-xs btn-ghost border border-base-300 hover:border-error hover:text-error"
                          phx-click="delete"
                          phx-value-id={tenant.id}
                          data-confirm={"Delete tenant \"#{tenant.name}\"? This cannot be undone."}
                        >
                          <.icon name="hero-trash" class="size-3.5" /> Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>

      <%= if @live_action in [:new, :edit] do %>
        <.modal id="tenant-modal" on_cancel={JS.patch(~p"/admin/tenants")}>
          <div id="tenant-modal-opener" phx-mounted={show_modal("tenant-modal")} />
          <h3 class="text-lg font-bold mb-4">
            {if @live_action == :new, do: "New Tenant", else: "Edit Tenant"}
          </h3>
          <.form for={@form} id="tenant-form" phx-change="validate" phx-submit="save">
            <div class="space-y-4">
              <.input
                field={@form[:name]}
                type="text"
                label="Tenant Name"
                placeholder="my-tenant"
                disabled={@live_action == :edit}
              />
              <.input
                field={@form[:description]}
                type="text"
                label="Description"
                placeholder="Optional description"
              />
            </div>
            <div class="flex justify-end gap-3 mt-6">
              <.link patch={~p"/admin/tenants"}>
                <button type="button" class="btn btn-sm btn-ghost">Cancel</button>
              </.link>
              <button
                type="submit"
                class="btn btn-sm border-2 border-nb shadow-nb-sm bg-gradient-nb text-white font-bold hover:opacity-90"
              >
                {if @live_action == :new, do: "Create Tenant", else: "Save Changes"}
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>
    </Layouts.app>
    """
  end
end
