defmodule PhaetonWeb.TypeLive do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    t = tenant || :all
    {:ok, types} = NGSI.get_types(t)

    type_details =
      Enum.map(types, fn type ->
        {:ok, info} = NGSI.get_type_info(type, t)
        %{name: type, entity_count: info.entity_count, attributes: info.attribute_details}
      end)
      |> Enum.sort_by(& &1.name)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phaeton.PubSub, "ngsi:entity_changes")
    end

    socket =
      socket
      |> assign(:page_title, "Types")
      |> assign(:type_details, type_details)

    {:ok, socket}
  end

  @impl true
  def handle_info({:entity_changed, _entity_id, _entity_data, _change_type}, socket) do
    {:noreply, reload_types(socket)}
  end

  def handle_info({:entity_deleted, _entity_id}, socket) do
    {:noreply, reload_types(socket)}
  end

  defp reload_types(socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    t = tenant || :all
    {:ok, types} = NGSI.get_types(t)

    type_details =
      Enum.map(types, fn type ->
        {:ok, info} = NGSI.get_type_info(type, t)
        %{name: type, entity_count: info.entity_count, attributes: info.attribute_details}
      end)
      |> Enum.sort_by(& &1.name)

    assign(socket, :type_details, type_details)
  end

  defp type_icon_color(idx) do
    colors = [
      {"bg-primary/10", "text-primary"},
      {"bg-secondary/10", "text-secondary"},
      {"bg-accent/10", "text-accent"},
      {"bg-info/10", "text-info"},
      {"bg-success/10", "text-success"},
      {"bg-warning/10", "text-warning"},
      {"bg-error/10", "text-error"}
    ]

    Enum.at(colors, rem(idx, length(colors)))
  end

  defp attr_type_badge("Property"), do: "badge-info"
  defp attr_type_badge("Relationship"), do: "badge-primary"
  defp attr_type_badge("GeoProperty"), do: "badge-success"
  defp attr_type_badge("LanguageProperty"), do: "badge-warning"
  defp attr_type_badge(_), do: "badge-ghost"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:types} current_scope={@current_scope}>
      <div class="space-y-4">
        <%!-- Header --%>
        <div>
          <h1 class="text-2xl font-bold tracking-tight heading-gradient">Entity Types</h1>
          <p class="text-sm opacity-50 mt-0.5">{length(@type_details)} registered types</p>
        </div>

        <%!-- Empty State --%>
        <%= if @type_details == [] do %>
          <div class="flex flex-col items-center py-16 opacity-40">
            <.icon name="hero-tag" class="size-12 mb-3 opacity-30" />
            <p class="text-sm">No entity types found</p>
            <p class="text-xs mt-1">Create entities via the API to register types</p>
          </div>
        <% end %>

        <%!-- Type Cards --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <%= for {td, idx} <- Enum.with_index(@type_details) do %>
            <% {bg, text} = type_icon_color(idx) %>
            <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-5 hover:border-primary/20 transition-all">
              <div class="flex items-start gap-4 mb-4">
                <div class={["w-11 h-11 rounded-xl flex items-center justify-center shrink-0", bg]}>
                  <.icon name="hero-tag" class={["size-5", text]} />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="font-bold text-lg">{td.name}</h3>
                  <div class="flex items-center gap-3 mt-1">
                    <span class="text-xs opacity-50 flex items-center gap-1">
                      <.icon name="hero-circle-stack" class="size-3" />
                      {td.entity_count} entities
                    </span>
                    <span class="text-xs opacity-50 flex items-center gap-1">
                      <.icon name="hero-cube" class="size-3" />
                      {length(td.attributes)} attributes
                    </span>
                  </div>
                </div>
                <.link
                  navigate={"/entities?type=#{td.name}"}
                  class="btn btn-sm btn-ghost gap-1"
                >
                  <.icon name="hero-eye" class="size-4" /> View
                </.link>
              </div>

              <%!-- Attribute List --%>
              <%= if td.attributes != [] do %>
                <div class="border-t border-base-300/50 pt-3">
                  <div class="text-xs font-semibold opacity-40 mb-2">Attributes</div>
                  <div class="space-y-1.5">
                    <%= for attr <- td.attributes do %>
                      <div class="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-base-300/30 transition-colors">
                        <span class="font-mono text-xs flex-1 truncate">{attr["attributeName"]}</span>
                        <span class="text-[10px] opacity-40">&times;{attr["attributeCount"]}</span>
                        <%= for atype <- attr["attributeTypes"] || [] do %>
                          <span class={["badge badge-xs badge-outline", attr_type_badge(atype)]}>
                            {atype}
                          </span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
