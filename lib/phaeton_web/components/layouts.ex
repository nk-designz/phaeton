defmodule PhaetonWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PhaetonWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the app layout with sidebar navigation.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :active_tab, :atom, default: nil, doc: "the currently active nav tab"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      id="app-drawer"
      class="drawer lg:drawer-open min-h-screen nb-page-bg"
      phx-hook=".SidebarToggle"
    >
      <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content flex flex-col">
        <%!-- Topbar (frosted glass) --%>
        <div class="navbar bg-base-200/70 topbar-glass border-b-2 border-nb sticky top-0 z-30 h-14 min-h-0">
          <div class="flex-none lg:hidden">
            <label for="sidebar-drawer" class="btn btn-sm btn-square btn-ghost">
              <.icon name="hero-bars-3" class="size-5" />
            </label>
          </div>
          <div class="flex-1 px-2 lg:hidden">
            <span class="font-bold tracking-tight">Phaeton</span>
          </div>
          <%!-- Desktop sidebar toggle --%>
          <div class="hidden lg:flex flex-none pl-3">
            <button
              class="relative flex border-2 border-nb bg-base-300 rounded-[5px] p-2 cursor-pointer opacity-60 hover:opacity-100 transition-opacity"
              phx-click={JS.dispatch("phx:sidebar-toggle", to: "#app-drawer")}
              title="Toggle sidebar"
            >
              <.icon name="hero-bars-3" class="size-4" />
            </button>
          </div>
          <div class="flex-1 hidden lg:block" />
          <div class="flex-none gap-2 pr-1 flex items-center">
            <%!-- Tenant selector --%>
            <%= if @current_scope && @current_scope.user do %>
              <form method="post" action="/users/active-tenant" class="flex items-center">
                <input
                  type="hidden"
                  name="_csrf_token"
                  value={Plug.CSRFProtection.get_csrf_token()}
                />
                <select
                  name="active_tenant"
                  onchange="this.form.submit()"
                  class="border-2 border-nb bg-base-300 rounded-[5px] text-xs font-semibold px-2 py-2 max-w-[10rem] focus:outline-none cursor-pointer appearance-none"
                >
                  <%= if @current_scope.role == "admin" do %>
                    <option value="" selected={@current_scope.active_tenant == :all}>
                      All Tenants
                    </option>
                  <% end %>
                  <%= for t <- @current_scope.allowed_tenants do %>
                    <option value={t} selected={@current_scope.active_tenant == t}>{t}</option>
                  <% end %>
                </select>
              </form>
            <% end %>
            <.theme_toggle />
          </div>
        </div>
        <%!-- Main content --%>
        <main class="flex-1 p-4 lg:p-6">
          {render_slot(@inner_block)}
        </main>
      </div>
      <div class="drawer-side z-40">
        <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <aside class="bg-base-200 min-h-full w-60 flex flex-col">
          <%!-- Branding (gradient bar) --%>
          <div class="sidebar-brand-gradient flex items-center gap-3 px-5 h-14 border-b-2 border-nb">
            <div class="w-8 h-8 rounded-[5px] bg-gradient-nb flex items-center justify-center border-2 border-nb shadow-nb-sm">
              <.icon name="hero-cube-transparent" class="size-[18px] text-white" />
            </div>
            <div>
              <div class="font-bold text-base leading-none tracking-tight text-gradient-nb">
                Phaeton
              </div>
              <div class="text-[10px] uppercase tracking-[0.15em] opacity-60 font-semibold mt-0.5">
                NGSI-LD Broker
              </div>
            </div>
          </div>
          <%!-- Nav --%>
          <nav class="flex-1 px-3 py-4">
            <ul class="menu menu-sm gap-0.5 w-full [&_li>a]:rounded-[5px] [&_li>a]:transition-all [&_li>a]:duration-150 [&_li>a]:border-2 [&_li>a]:border-transparent [&_li>a.active]:border-nb [&_li>a.active]:shadow-nb-sm [&_li>a.active]:bg-gradient-nb [&_li>a.active]:text-white [&_li>a.active]:font-bold">
              <%!-- Overview --%>
              <li>
                <.link navigate="/" class={[@active_tab == :dashboard && "active"]}>
                  <.icon name="hero-squares-2x2" class="size-[18px]" />
                  <span>Dashboard</span>
                </.link>
              </li>
              <%!-- Data --%>
              <li class="menu-title mt-3 text-[10px] uppercase tracking-widest opacity-40 font-bold px-2">
                Data
              </li>
              <li>
                <.link navigate="/entities" class={[@active_tab == :entities && "active"]}>
                  <.icon name="hero-circle-stack" class="size-[18px]" />
                  <span>Entities</span>
                </.link>
              </li>
              <li>
                <.link navigate="/types" class={[@active_tab == :types && "active"]}>
                  <.icon name="hero-tag" class="size-[18px]" />
                  <span>Types</span>
                </.link>
              </li>
              <%!-- Visualize --%>
              <li class="menu-title mt-3 text-[10px] uppercase tracking-widest opacity-40 font-bold px-2">
                Visualize
              </li>
              <li>
                <.link navigate="/map" class={[@active_tab == :map && "active"]}>
                  <.icon name="hero-map" class="size-[18px]" />
                  <span>Map</span>
                </.link>
              </li>
              <li>
                <.link navigate="/charts" class={[@active_tab == :charts && "active"]}>
                  <.icon name="hero-chart-bar" class="size-[18px]" />
                  <span>Charts</span>
                </.link>
              </li>
              <%= if @current_scope && @current_scope.role == "admin" do %>
                <li>
                  <.link navigate="/graph" class={[@active_tab == :graph && "active"]}>
                    <.icon name="hero-share" class="size-[18px]" />
                    <span>Graph Explorer</span>
                  </.link>
                </li>
              <% end %>
              <%!-- Query --%>
              <%= if @current_scope && @current_scope.role == "admin" do %>
                <li class="menu-title mt-3 text-[10px] uppercase tracking-widest opacity-40 font-bold px-2">
                  Query
                </li>
                <li>
                  <.link navigate="/sparql" class={[@active_tab == :sparql && "active"]}>
                    <.icon name="hero-command-line" class="size-[18px]" />
                    <span>SPARQL</span>
                  </.link>
                </li>
              <% end %>
              <%!-- System --%>
              <li class="menu-title mt-3 text-[10px] uppercase tracking-widest opacity-40 font-bold px-2">
                System
              </li>
              <%= if @current_scope && @current_scope.role == "admin" do %>
                <li>
                  <.link navigate="/cluster" class={[@active_tab == :cluster && "active"]}>
                    <.icon name="hero-server-stack" class="size-[18px]" />
                    <span>Cluster</span>
                  </.link>
                </li>
              <% end %>
              <li>
                <.link navigate="/subscriptions" class={[@active_tab == :subscriptions && "active"]}>
                  <.icon name="hero-bell" class="size-[18px]" />
                  <span>Subscriptions</span>
                </.link>
              </li>
              <%!-- Admin (admins only) --%>
              <%= if @current_scope && @current_scope.role == "admin" do %>
                <li class="menu-title mt-3 text-[10px] uppercase tracking-widest opacity-40 font-bold px-2">
                  Admin
                </li>
                <li>
                  <.link navigate="/admin/tenants" class={[@active_tab == :admin_tenants && "active"]}>
                    <.icon name="hero-building-office" class="size-[18px]" />
                    <span>Tenants</span>
                  </.link>
                </li>
                <li>
                  <.link navigate="/admin/users" class={[@active_tab == :admin_users && "active"]}>
                    <.icon name="hero-users" class="size-[18px]" />
                    <span>Users</span>
                  </.link>
                </li>
                <li>
                  <.link navigate="/admin/groups" class={[@active_tab == :admin_groups && "active"]}>
                    <.icon name="hero-user-group" class="size-[18px]" />
                    <span>Groups</span>
                  </.link>
                </li>
                <li>
                  <.link
                    navigate="/admin/settings"
                    class={[@active_tab == :admin_settings && "active"]}
                  >
                    <.icon name="hero-cog-6-tooth" class="size-[18px]" />
                    <span>Settings</span>
                  </.link>
                </li>
              <% end %>
            </ul>
          </nav>
          <%!-- Footer --%>
          <div class="px-4 py-3 border-t-2 border-nb">
            <%= if @current_scope && @current_scope.user do %>
              <div class="flex items-start gap-2 mb-2">
                <div class="w-7 h-7 rounded-[5px] bg-gradient-nb flex items-center justify-center border-2 border-nb shrink-0 mt-0.5">
                  <.icon name="hero-user" class="size-3.5 text-white" />
                </div>
                <div class="min-w-0">
                  <div class="text-[11px] font-semibold truncate leading-tight">
                    {@current_scope.user.email}
                  </div>
                  <div class="flex items-center gap-1 mt-0.5 flex-wrap">
                    <span class="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded text-[9px] font-bold uppercase tracking-wider bg-nb-accent/20 text-nb-accent border border-nb-accent/40">
                      <.icon name="hero-building-office" class="size-2.5" />
                      {@current_scope.tenant}
                    </span>
                    <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-bold uppercase tracking-wider bg-base-300 opacity-60">
                      {@current_scope.role}
                    </span>
                  </div>
                </div>
              </div>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="flex items-center gap-2 w-full text-[11px] opacity-50 hover:opacity-100 font-semibold transition-opacity"
              >
                <.icon name="hero-arrow-left-on-rectangle" class="size-3.5" />
                <span>Log out</span>
              </.link>
            <% else %>
              <.link
                navigate={~p"/users/log-in"}
                class="flex items-center gap-2 w-full text-[11px] opacity-60 hover:opacity-100 font-semibold transition-opacity"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-3.5" />
                <span>Log in</span>
              </.link>
            <% end %>
            <div class="flex items-center gap-2 text-[11px] opacity-40 font-semibold mt-2">
              <.icon name="hero-server-stack" class="size-3.5" />
              <span>Phoenix v{Application.spec(:phoenix, :vsn)}</span>
            </div>
          </div>
        </aside>
      </div>
    </div>
    <.flash_group flash={@flash} />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SidebarToggle">
      export default {
        mounted() {
          const KEY = 'phx:sidebar';
          if (localStorage.getItem(KEY) === 'collapsed' && window.innerWidth >= 1024) {
            this.el.classList.remove('lg:drawer-open');
          }
          this._toggle = () => {
            const open = this.el.classList.contains('lg:drawer-open');
            this.el.classList.toggle('lg:drawer-open', !open);
            localStorage.setItem(KEY, open ? 'collapsed' : 'open');
          };
          this.el.addEventListener('phx:sidebar-toggle', this._toggle);
        },
        destroyed() {
          this.el.removeEventListener('phx:sidebar-toggle', this._toggle);
        }
      }
    </script>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center border-2 border-nb bg-base-300 rounded-[5px] overflow-hidden">
      <div class="absolute w-1/3 h-full bg-primary left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left] duration-200" />

      <button
        class="relative flex p-2 cursor-pointer w-1/3 z-10"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="relative flex p-2 cursor-pointer w-1/3 z-10"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="relative flex p-2 cursor-pointer w-1/3 z-10"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
