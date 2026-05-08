defmodule PhaetonWeb.DashboardLive do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    t = tenant || :all
    stats = NGSI.get_stats(t)
    {:ok, entities, _meta} = NGSI.query_entities(%{"limit" => "8"}, t)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phaeton.PubSub, "ngsi:entity_changes")
    end

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:stats, stats)
      |> assign(:recent_entities, entities)

    {:ok, socket}
  end

  @impl true
  def handle_info({:entity_changed, _entity_id, _entity_data, _change_type}, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    t = tenant || :all
    stats = NGSI.get_stats(t)
    {:ok, entities, _meta} = NGSI.query_entities(%{"limit" => "8"}, t)

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:recent_entities, entities)}
  end

  def handle_info({:entity_deleted, _entity_id}, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    t = tenant || :all
    stats = NGSI.get_stats(t)
    {:ok, entities, _meta} = NGSI.query_entities(%{"limit" => "8"}, t)

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:recent_entities, entities)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:dashboard} current_scope={@current_scope}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div>
          <h1 class="text-2xl font-bold tracking-tight heading-gradient">Dashboard</h1>
          <p class="text-sm opacity-60 mt-1">NGSI-LD Context Broker overview</p>
        </div>

        <%!-- Stats Grid --%>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <div class="stat-card card bg-base-200 p-4">
            <div class="flex items-center gap-3">
              <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                <.icon name="hero-circle-stack" class="size-5 text-white" />
              </div>
              <div>
                <div class="text-2xl font-bold">{@stats.entity_count}</div>
                <div class="text-xs opacity-60 font-semibold">Entities</div>
              </div>
            </div>
          </div>
          <div class="stat-card card bg-base-200 p-4">
            <div class="flex items-center gap-3">
              <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                <.icon name="hero-tag" class="size-5 text-white" />
              </div>
              <div>
                <div class="text-2xl font-bold">{@stats.type_count}</div>
                <div class="text-xs opacity-60 font-semibold">Types</div>
              </div>
            </div>
          </div>
          <div class="stat-card card bg-base-200 p-4">
            <div class="flex items-center gap-3">
              <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                <.icon name="hero-bell" class="size-5 text-white" />
              </div>
              <div>
                <div class="text-2xl font-bold">{@stats.subscription_count}</div>
                <div class="text-xs opacity-60 font-semibold">Subscriptions</div>
              </div>
            </div>
          </div>
          <div class="stat-card card bg-base-200 p-4">
            <div class="flex items-center gap-3">
              <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                <.icon name="hero-share" class="size-5 text-white" />
              </div>
              <div>
                <div class="text-2xl font-bold">{@stats.triple_count}</div>
                <div class="text-xs opacity-60 font-semibold">RDF Triples</div>
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-2 lg:grid-cols-2 gap-4">
          <div class="stat-card card bg-base-200 p-4">
            <div class="flex items-center gap-3">
              <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                <.icon name="hero-clock" class="size-5 text-white" />
              </div>
              <div>
                <div class="text-2xl font-bold">{@stats.temporal_count}</div>
                <div class="text-xs opacity-60 font-semibold">Temporal Records</div>
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <%!-- Type Distribution --%>
          <div class="card-glass p-5 lg:col-span-1">
            <h2 class="font-bold text-sm mb-4 flex items-center gap-2">
              <.icon name="hero-chart-bar" class="size-4" /> Type Distribution
            </h2>
            <%= if @stats.type_counts == %{} do %>
              <div class="text-sm opacity-40 text-center py-6">No entities yet</div>
            <% else %>
              <div class="space-y-3">
                <%= for {type, count} <- Enum.sort_by(@stats.type_counts, fn {_, c} -> c end, :desc) do %>
                  <div>
                    <div class="flex justify-between items-center mb-1">
                      <span class="text-sm font-semibold">{type}</span>
                      <span class="text-xs font-bold opacity-60">{count}</span>
                    </div>
                    <div class="w-full bg-base-300 h-3 border-2 border-nb overflow-hidden">
                      <div
                        class="bg-gradient-nb h-full transition-all duration-500"
                        style={"width: #{min(100, count / max(Map.values(@stats.type_counts) |> Enum.max(), 1) * 100)}%"}
                      >
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Recent Entities --%>
          <div class="card-glass p-5 lg:col-span-2">
            <div class="flex items-center justify-between mb-4">
              <h2 class="font-bold text-sm flex items-center gap-2">
                <.icon name="hero-clock" class="size-4" /> Recent Entities
              </h2>
              <.link navigate="/entities" class="text-xs font-bold text-primary hover:underline">
                View all &rarr;
              </.link>
            </div>
            <%= if @recent_entities == [] do %>
              <div class="text-sm opacity-40 text-center py-6">
                No entities created yet. Use the API to create your first entity.
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr class="text-xs font-bold">
                      <th>ID</th>
                      <th>Type</th>
                      <th class="hidden sm:table-cell">Attributes</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for entity <- @recent_entities do %>
                      <tr class="hover:bg-base-300/50 transition-colors">
                        <td class="font-mono text-xs max-w-48 truncate">{entity["id"]}</td>
                        <td>
                          <span class="badge badge-sm badge-primary">{entity["type"]}</span>
                        </td>
                        <td class="hidden sm:table-cell text-xs font-semibold opacity-60">
                          {entity
                          |> Map.drop(["id", "type", "createdAt", "modifiedAt", "@context"])
                          |> map_size()}
                        </td>
                        <td class="text-right">
                          <.link
                            navigate={"/entities/#{URI.encode_www_form(entity["id"])}"}
                            class="btn btn-xs btn-ghost"
                          >
                            <.icon name="hero-eye" class="size-3.5" />
                          </.link>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Quick Actions --%>
        <div class="card-glass p-5">
          <h2 class="font-bold text-sm mb-3 flex items-center gap-2">
            <.icon name="hero-bolt" class="size-4" /> Quick Actions
          </h2>
          <div class="flex flex-wrap gap-3">
            <.link navigate="/graph" class="btn btn-sm bg-gradient-nb text-white border-nb gap-1.5">
              <.icon name="hero-share" class="size-4" /> Explore Graph
            </.link>
            <.link navigate="/entities" class="btn btn-sm gap-1.5">
              <.icon name="hero-circle-stack" class="size-4" /> Browse Entities
            </.link>
            <.link navigate="/types" class="btn btn-sm gap-1.5">
              <.icon name="hero-tag" class="size-4" /> View Types
            </.link>
            <a
              href="/ngsi-ld/v1/entities"
              target="_blank"
              class="btn btn-sm gap-1.5"
            >
              <.icon name="hero-code-bracket" class="size-4" /> API Endpoint
            </a>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
