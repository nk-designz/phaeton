defmodule PhaetonWeb.Admin.GroupLive do
  use PhaetonWeb, :live_view

  alias Phaeton.Accounts

  @impl true
  def mount(_params, _session, socket) do
    tenants = Accounts.list_tenants()
    tenant_options = Enum.map(tenants, fn t -> {t.name, t.name} end)

    {:ok,
     socket
     |> assign(:page_title, "Groups")
     |> assign(:tenant_options, tenant_options)
     |> assign(:form, nil)
     |> assign(:group, nil)
     |> assign(:members, [])
     |> assign(:non_members, [])
     |> load_groups()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, group: nil, form: nil, members: [], non_members: [])
  end

  defp apply_action(socket, :new, _params) do
    group = %Accounts.Group{}

    assign(socket,
      group: group,
      form: to_form(Accounts.change_group(group)),
      members: [],
      non_members: []
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    group = Accounts.get_group!(id)

    assign(socket,
      group: group,
      form: to_form(Accounts.change_group(group)),
      members: [],
      non_members: []
    )
  end

  defp apply_action(socket, :members, %{"id" => id}) do
    group = Accounts.get_group!(id)
    members = Accounts.list_group_members(id)
    non_members = Accounts.list_users_not_in_group(id)
    assign(socket, group: group, form: nil, members: members, non_members: non_members)
  end

  @impl true
  def handle_event("validate", %{"group" => params}, socket) do
    changeset = Accounts.change_group(socket.assigns.group, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"group" => params}, socket) do
    save_group(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    group = Accounts.get_group!(id)

    case Accounts.delete_group(group) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group \"#{group.name}\" deleted.")
         |> load_groups()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete group.")}
    end
  end

  def handle_event("add_member", %{"user_id" => user_id}, socket) do
    group = socket.assigns.group

    case Accounts.add_group_member(group.id, String.to_integer(user_id)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:members, Accounts.list_group_members(group.id))
         |> assign(:non_members, Accounts.list_users_not_in_group(group.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add member.")}
    end
  end

  def handle_event("remove_member", %{"user_id" => user_id}, socket) do
    group = socket.assigns.group
    Accounts.remove_group_member(group.id, String.to_integer(user_id))

    {:noreply,
     socket
     |> assign(:members, Accounts.list_group_members(group.id))
     |> assign(:non_members, Accounts.list_users_not_in_group(group.id))}
  end

  defp save_group(socket, :new, params) do
    case Accounts.create_group(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group created successfully.")
         |> push_patch(to: ~p"/admin/groups")
         |> load_groups()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_group(socket, :edit, params) do
    case Accounts.update_group(socket.assigns.group, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group updated.")
         |> push_patch(to: ~p"/admin/groups")
         |> load_groups()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp load_groups(socket) do
    groups = Accounts.list_groups()
    counts = Map.new(groups, fn g -> {g.id, Accounts.group_member_count(g.id)} end)
    assign(socket, groups: groups, member_counts: counts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:admin_groups} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight heading-gradient">Groups</h1>
            <p class="text-sm opacity-60 mt-1">Organize users into groups for access control</p>
          </div>
          <.link patch={~p"/admin/groups/new"}>
            <button class="btn btn-sm border-2 border-nb shadow-nb-sm bg-gradient-nb text-white font-bold hover:opacity-90 transition-opacity">
              <.icon name="hero-plus" class="size-4" /> New Group
            </button>
          </.link>
        </div>

        <div class="card bg-base-200 border-2 border-nb shadow-nb rounded-[10px] overflow-hidden">
          <%= if @groups == [] do %>
            <div class="p-12 text-center opacity-50">
              <.icon name="hero-user-group" class="size-10 mx-auto mb-3" />
              <p class="font-semibold">No groups yet</p>
              <p class="text-sm mt-1">Create groups to organize users</p>
            </div>
          <% else %>
            <table class="table table-sm w-full">
              <thead>
                <tr class="border-b-2 border-nb text-[11px] uppercase tracking-widest opacity-50 font-bold">
                  <th class="px-4 py-3">Name</th>
                  <th class="px-4 py-3">Tenant</th>
                  <th class="px-4 py-3">Description</th>
                  <th class="px-4 py-3">Members</th>
                  <th class="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for group <- @groups do %>
                  <tr class="border-b border-base-300 hover:bg-base-300/40 transition-colors">
                    <td class="px-4 py-3 font-semibold text-sm">{group.name}</td>
                    <td class="px-4 py-3">
                      <span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-bold bg-nb-accent/20 text-nb-accent border border-nb-accent/40">
                        <.icon name="hero-building-office" class="size-2.5" />
                        {group.tenant}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-sm opacity-70">{group.description || "—"}</td>
                    <td class="px-4 py-3">
                      <.link
                        patch={~p"/admin/groups/#{group.id}/members"}
                        class="badge badge-sm badge-ghost font-mono hover:badge-primary cursor-pointer"
                      >
                        {@member_counts[group.id] || 0} members
                      </.link>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <div class="flex items-center justify-end gap-2">
                        <.link patch={~p"/admin/groups/#{group.id}/members"}>
                          <button class="btn btn-xs btn-ghost border border-base-300 hover:border-nb">
                            <.icon name="hero-user-group" class="size-3.5" /> Members
                          </button>
                        </.link>
                        <.link patch={~p"/admin/groups/#{group.id}/edit"}>
                          <button class="btn btn-xs btn-ghost border border-base-300 hover:border-nb">
                            <.icon name="hero-pencil-square" class="size-3.5" /> Edit
                          </button>
                        </.link>
                        <button
                          class="btn btn-xs btn-ghost border border-base-300 hover:border-error hover:text-error"
                          phx-click="delete"
                          phx-value-id={group.id}
                          data-confirm={"Delete group \"#{group.name}\"? This cannot be undone."}
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

      <%!-- Create / Edit modal --%>
      <%= if @live_action in [:new, :edit] do %>
        <.modal id="group-modal" on_cancel={JS.patch(~p"/admin/groups")}>
          <div id="group-modal-opener" phx-mounted={show_modal("group-modal")} />
          <h3 class="text-lg font-bold mb-4">
            {if @live_action == :new, do: "New Group", else: "Edit Group"}
          </h3>
          <.form for={@form} id="group-form" phx-change="validate" phx-submit="save">
            <div class="space-y-4">
              <.input field={@form[:name]} type="text" label="Group Name" placeholder="my-group" />
              <.input
                field={@form[:tenant]}
                type="select"
                label="Tenant"
                options={@tenant_options}
                prompt="Select tenant…"
              />
              <.input
                field={@form[:description]}
                type="text"
                label="Description"
                placeholder="Optional description"
              />
            </div>
            <div class="flex justify-end gap-3 mt-6">
              <.link patch={~p"/admin/groups"}>
                <button type="button" class="btn btn-sm btn-ghost">Cancel</button>
              </.link>
              <button
                type="submit"
                class="btn btn-sm border-2 border-nb shadow-nb-sm bg-gradient-nb text-white font-bold hover:opacity-90"
              >
                {if @live_action == :new, do: "Create Group", else: "Save Changes"}
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>

      <%!-- Members modal --%>
      <%= if @live_action == :members do %>
        <.modal id="members-modal" on_cancel={JS.patch(~p"/admin/groups")}>
          <div id="members-modal-opener" phx-mounted={show_modal("members-modal")} />
          <h3 class="text-lg font-bold mb-4">Members — {@group.name}</h3>
          <div class="space-y-4">
            <%!-- Current members --%>
            <div>
              <h3 class="text-xs font-bold uppercase tracking-widest opacity-50 mb-2">
                Current Members
              </h3>
              <%= if @members == [] do %>
                <p class="text-sm opacity-50 py-2">No members yet.</p>
              <% else %>
                <ul class="space-y-1">
                  <%= for user <- @members do %>
                    <li class="flex items-center justify-between py-1.5 px-2 rounded-[5px] bg-base-300/40">
                      <div class="flex items-center gap-2">
                        <div class="w-5 h-5 rounded-[3px] bg-gradient-nb flex items-center justify-center border border-nb shrink-0">
                          <.icon name="hero-user" class="size-2.5 text-white" />
                        </div>
                        <span class="text-sm font-semibold">{user.email}</span>
                        <span class="text-[10px] opacity-50">{user.tenant}</span>
                      </div>
                      <button
                        class="btn btn-xs btn-ghost text-error hover:bg-error/10"
                        phx-click="remove_member"
                        phx-value-user_id={user.id}
                      >
                        <.icon name="hero-x-mark" class="size-3" />
                      </button>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>

            <%!-- Add members --%>
            <%= if @non_members != [] do %>
              <div>
                <h3 class="text-xs font-bold uppercase tracking-widest opacity-50 mb-2">Add Users</h3>
                <ul class="space-y-1 max-h-48 overflow-y-auto">
                  <%= for user <- @non_members do %>
                    <li class="flex items-center justify-between py-1.5 px-2 rounded-[5px] hover:bg-base-300/40">
                      <div class="flex items-center gap-2">
                        <span class="text-sm">{user.email}</span>
                        <span class="text-[10px] opacity-50">{user.tenant}</span>
                      </div>
                      <button
                        class="btn btn-xs btn-ghost border border-base-300 hover:border-nb"
                        phx-click="add_member"
                        phx-value-user_id={user.id}
                      >
                        <.icon name="hero-plus" class="size-3" /> Add
                      </button>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% end %>
          </div>
          <div class="flex justify-end mt-6">
            <.link patch={~p"/admin/groups"}>
              <button type="button" class="btn btn-sm btn-ghost">Done</button>
            </.link>
          </div>
        </.modal>
      <% end %>
    </Layouts.app>
    """
  end
end
