defmodule PhaetonWeb.Admin.UserLive do
  use PhaetonWeb, :live_view

  alias Phaeton.Accounts

  @roles [
    {"Admin", "admin"},
    {"Agent", "agent"},
    {"Data Provider", "data_provider"},
    {"Data Consumer", "data_consumer"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    tenants = Accounts.list_tenants()
    tenant_options = Enum.map(tenants, fn t -> {t.name, t.name} end)

    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:roles, @roles)
     |> assign(:tenant_options, tenant_options)
     |> assign(:form, nil)
     |> assign(:tokens, [])
     |> assign(:new_plain_token, nil)
     |> assign(:token_form, to_form(%{"name" => ""}, as: :token))
     |> load_users()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, user: nil, form: nil)
  end

  defp apply_action(socket, :new, _params) do
    user = %Accounts.User{}
    assign(socket, user: user, form: to_form(Accounts.change_admin_create_user(user)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = Accounts.get_user!(id)
    assign(socket, user: user, form: to_form(Accounts.change_admin_edit_user(user)))
  end

  defp apply_action(socket, :tokens, %{"id" => id}) do
    user = Accounts.get_user!(id)
    tokens = Accounts.list_api_tokens(user)

    assign(socket,
      user: user,
      form: nil,
      tokens: tokens,
      new_plain_token: nil,
      token_form: to_form(%{"name" => ""}, as: :token)
    )
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      case socket.assigns.live_action do
        :new -> Accounts.change_admin_create_user(socket.assigns.user, params)
        :edit -> Accounts.change_admin_edit_user(socket.assigns.user, params)
      end

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    save_user(socket, socket.assigns.live_action, params)
  end

  def handle_event("generate_token", %{"token" => %{"name" => name}}, socket) do
    case Accounts.generate_api_token(socket.assigns.user, name) do
      {:ok, plain_token, _} ->
        tokens = Accounts.list_api_tokens(socket.assigns.user)

        {:noreply,
         assign(socket,
           tokens: tokens,
           new_plain_token: plain_token,
           token_form: to_form(%{"name" => ""}, as: :token)
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not generate token.")}
    end
  end

  def handle_event("delete_token", %{"id" => id}, socket) do
    token = Accounts.get_api_token!(String.to_integer(id))
    {:ok, _} = Accounts.delete_api_token(token)
    tokens = Accounts.list_api_tokens(socket.assigns.user)
    {:noreply, assign(socket, :tokens, tokens)}
  end

  def handle_event("dismiss_token", _, socket) do
    {:noreply, assign(socket, :new_plain_token, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if user.id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "You cannot delete your own account.")}
    else
      case Accounts.admin_delete_user(user) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "User #{user.email} deleted.")
           |> load_users()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete user.")}
      end
    end
  end

  defp save_user(socket, :new, params) do
    case Accounts.admin_create_user(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User created successfully.")
         |> push_patch(to: ~p"/admin/users")
         |> load_users()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_user(socket, :edit, params) do
    case Accounts.admin_update_user(socket.assigns.user, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated.")
         |> push_patch(to: ~p"/admin/users")
         |> load_users()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp load_users(socket) do
    assign(socket, :users, Accounts.list_users())
  end

  defp role_label(role) do
    case role do
      "admin" -> "Admin"
      "agent" -> "Agent"
      "data_provider" -> "Data Provider"
      "data_consumer" -> "Data Consumer"
      other -> other
    end
  end

  defp role_class(role) do
    case role do
      "admin" -> "bg-error/20 text-error border-error/40"
      "agent" -> "bg-info/20 text-info border-info/40"
      "data_provider" -> "bg-warning/20 text-warning border-warning/40"
      _ -> "bg-base-300 opacity-60"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:admin_users} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight heading-gradient">Users</h1>
            <p class="text-sm opacity-60 mt-1">Manage user accounts, roles and tenant assignments</p>
          </div>
          <.link patch={~p"/admin/users/new"}>
            <button class="btn btn-sm border-2 border-nb shadow-nb-sm bg-gradient-nb text-white font-bold hover:opacity-90 transition-opacity">
              <.icon name="hero-plus" class="size-4" /> New User
            </button>
          </.link>
        </div>

        <div class="card bg-base-200 border-2 border-nb shadow-nb rounded-[10px] overflow-hidden">
          <%= if @users == [] do %>
            <div class="p-12 text-center opacity-50">
              <.icon name="hero-users" class="size-10 mx-auto mb-3" />
              <p class="font-semibold">No users yet</p>
            </div>
          <% else %>
            <table class="table table-sm w-full">
              <thead>
                <tr class="border-b-2 border-nb text-[11px] uppercase tracking-widest opacity-50 font-bold">
                  <th class="px-4 py-3">Email</th>
                  <th class="px-4 py-3">Tenant</th>
                  <th class="px-4 py-3">Role</th>
                  <th class="px-4 py-3">Joined</th>
                  <th class="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for user <- @users do %>
                  <tr class="border-b border-base-300 hover:bg-base-300/40 transition-colors">
                    <td class="px-4 py-3">
                      <div class="flex items-center gap-2">
                        <div class="w-6 h-6 rounded-[4px] bg-gradient-nb flex items-center justify-center border border-nb shrink-0">
                          <.icon name="hero-user" class="size-3 text-white" />
                        </div>
                        <span class="text-sm font-semibold">{user.email}</span>
                        <%= if @current_scope.user.id == user.id do %>
                          <span class="badge badge-xs badge-ghost">you</span>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-4 py-3">
                      <span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-bold bg-nb-accent/20 text-nb-accent border border-nb-accent/40">
                        <.icon name="hero-building-office" class="size-2.5" />
                        {user.tenant}
                      </span>
                    </td>
                    <td class="px-4 py-3">
                      <span class={"inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-bold border #{role_class(user.role)}"}>
                        {role_label(user.role)}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-sm opacity-50 font-mono text-xs">
                      {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
                    </td>
                    <td class="px-4 py-3 text-right">
                      <div class="flex items-center justify-end gap-2">
                        <.link patch={~p"/admin/users/#{user.id}/edit"}>
                          <button class="btn btn-xs btn-ghost border border-base-300 hover:border-nb">
                            <.icon name="hero-pencil-square" class="size-3.5" /> Edit
                          </button>
                        </.link>
                        <.link patch={~p"/admin/users/#{user.id}/tokens"}>
                          <button class="btn btn-xs btn-ghost border border-base-300 hover:border-nb">
                            <.icon name="hero-key" class="size-3.5" /> Tokens
                          </button>
                        </.link>
                        <%= if @current_scope.user.id != user.id do %>
                          <button
                            class="btn btn-xs btn-ghost border border-base-300 hover:border-error hover:text-error"
                            phx-click="delete"
                            phx-value-id={user.id}
                            data-confirm={"Delete user #{user.email}? This cannot be undone."}
                          >
                            <.icon name="hero-trash" class="size-3.5" /> Delete
                          </button>
                        <% end %>
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
        <.modal id="user-modal" on_cancel={JS.patch(~p"/admin/users")}>
          <div id="user-modal-opener" phx-mounted={show_modal("user-modal")} />
          <h3 class="text-lg font-bold mb-4">
            {if @live_action == :new, do: "New User", else: "Edit User"}
          </h3>
          <.form for={@form} id="user-form" phx-change="validate" phx-submit="save">
            <div class="space-y-4">
              <%= if @live_action == :new do %>
                <.input
                  field={@form[:email]}
                  type="email"
                  label="Email"
                  placeholder="user@example.com"
                />
                <.input field={@form[:password]} type="password" label="Password" />
                <.input
                  field={@form[:password_confirmation]}
                  type="password"
                  label="Confirm Password"
                />
              <% else %>
                <div class="p-3 bg-base-300 rounded-[5px] text-sm font-semibold opacity-70">
                  {@user.email}
                </div>
              <% end %>
              <.input
                field={@form[:tenant]}
                type="select"
                label="Tenant"
                options={@tenant_options}
                prompt="Select tenant…"
              />
              <.input
                field={@form[:role]}
                type="select"
                label="Role"
                options={@roles}
                prompt="Select role…"
              />
            </div>
            <div class="flex justify-end gap-3 mt-6">
              <.link patch={~p"/admin/users"}>
                <button type="button" class="btn btn-sm btn-ghost">Cancel</button>
              </.link>
              <button
                type="submit"
                class="btn btn-sm border-2 border-nb shadow-nb-sm bg-gradient-nb text-white font-bold hover:opacity-90"
              >
                {if @live_action == :new, do: "Create User", else: "Save Changes"}
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>

      <%= if @live_action == :tokens do %>
        <.modal id="tokens-modal" on_cancel={JS.patch(~p"/admin/users")}>
          <div id="tokens-modal-opener" phx-mounted={show_modal("tokens-modal")} />
          <div class="flex items-center gap-3 mb-5">
            <div class="w-8 h-8 rounded-[5px] bg-gradient-nb flex items-center justify-center border border-nb">
              <.icon name="hero-key" class="size-4 text-white" />
            </div>
            <div>
              <h3 class="text-lg font-bold leading-tight">API Tokens</h3>
              <p class="text-xs opacity-50">{@user.email}</p>
            </div>
          </div>

          <%!-- New token reveal --%>
          <%= if @new_plain_token do %>
            <div class="mb-5 p-3 rounded-[6px] bg-success/10 border border-success/40">
              <p class="text-xs font-bold text-success mb-1.5">
                Token generated — copy it now, it won't be shown again:
              </p>
              <div class="flex items-center gap-2">
                <code class="flex-1 font-mono text-xs break-all bg-base-300 rounded px-2 py-1.5">
                  {@new_plain_token}
                </code>
                <button
                  type="button"
                  class="btn btn-xs btn-ghost shrink-0"
                  phx-click={JS.dispatch("phx:copy", detail: %{text: @new_plain_token})}
                >
                  <.icon name="hero-clipboard" class="size-3.5" />
                </button>
              </div>
              <button
                type="button"
                class="mt-2 text-xs opacity-50 hover:opacity-80"
                phx-click="dismiss_token"
              >
                Dismiss
              </button>
            </div>
          <% end %>

          <%!-- Generate form --%>
          <.form for={@token_form} id="token-name-form" phx-submit="generate_token">
            <div class="flex gap-2 items-end">
              <div class="flex-1">
                <.input
                  field={@token_form[:name]}
                  type="text"
                  label="New token name"
                  placeholder="e.g. CI/CD Pipeline"
                />
              </div>
              <button
                type="submit"
                class="btn btn-sm border-2 border-nb shadow-nb-sm bg-gradient-nb text-white font-bold hover:opacity-90 shrink-0"
              >
                <.icon name="hero-plus" class="size-3.5" /> Generate
              </button>
            </div>
          </.form>

          <%!-- Token list --%>
          <div class="mt-5">
            <%= if @tokens == [] do %>
              <div class="py-8 text-center opacity-40 text-sm">
                <.icon name="hero-key" class="size-8 mx-auto mb-2" /> No tokens yet
              </div>
            <% else %>
              <table class="table table-sm w-full">
                <thead>
                  <tr class="border-b border-base-300 text-[10px] uppercase tracking-widest opacity-40 font-bold">
                    <th class="px-2 py-2">Name</th>
                    <th class="px-2 py-2">Created</th>
                    <th class="px-2 py-2 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for token <- @tokens do %>
                    <tr class="border-b border-base-300 hover:bg-base-300/40">
                      <td class="px-2 py-2 font-semibold text-sm">{token.name}</td>
                      <td class="px-2 py-2 text-xs font-mono opacity-50">
                        {Calendar.strftime(token.inserted_at, "%Y-%m-%d %H:%M")}
                      </td>
                      <td class="px-2 py-2 text-right">
                        <button
                          class="btn btn-xs btn-ghost border border-base-300 hover:border-error hover:text-error"
                          phx-click="delete_token"
                          phx-value-id={token.id}
                          data-confirm={"Revoke token '#{token.name}'? This cannot be undone."}
                        >
                          <.icon name="hero-trash" class="size-3" /> Revoke
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>

          <div class="flex justify-end mt-4">
            <.link patch={~p"/admin/users"}>
              <button type="button" class="btn btn-sm btn-ghost">Close</button>
            </.link>
          </div>
        </.modal>
      <% end %>
    </Layouts.app>
    """
  end
end
