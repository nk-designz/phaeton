defmodule PhaetonWeb.EntityLive.Index do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI
  alias Phaeton.Store

  @impl true
  def mount(_params, _session, socket) do
    {:ok, types} = NGSI.get_types()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phaeton.PubSub, "ngsi:entity_changes")
    end

    socket =
      socket
      |> assign(:page_title, "Entities")
      |> assign(:types, types)
      |> assign(:search, "")
      |> assign(:type_filter, nil)
      |> assign(:total_count, 0)
      |> assign(:current_page, 1)
      |> assign(:per_page, 20)
      |> assign(:create_form, to_form(%{"id" => "", "type" => "", "json" => ""}, as: :entity))
      |> assign(:create_mode, :form)
      |> assign(:create_attrs, [])
      |> stream(:entities, [],
        dom_id: fn entity ->
          "entity-" <> String.replace(entity["id"], ~r/[^a-zA-Z0-9]/, "-")
        end
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = parse_int(params["page"], 1)
    type_filter = params["type"]
    search = params["q"] || ""
    per_page = socket.assigns.per_page
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant

    query_params =
      %{
        "limit" => to_string(per_page),
        "offset" => to_string((page - 1) * per_page),
        "count" => "true"
      }
      |> maybe_put("type", type_filter)
      |> maybe_put("id", if(search != "", do: search, else: nil))

    {:ok, entities, meta} = NGSI.query_entities(query_params, tenant || :all)

    page_title =
      case socket.assigns.live_action do
        :new -> "New Entity"
        _ -> "Entities"
      end

    socket =
      socket
      |> assign(:page_title, page_title)
      |> assign(:current_page, page)
      |> assign(:type_filter, type_filter)
      |> assign(:search, search)
      |> assign(:total_count, meta.total_count)
      |> stream(:entities, entities, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:entity_changed, _entity_id, _entity_data, _change_type}, socket) do
    reload_entities(socket)
  end

  def handle_info({:entity_deleted, _entity_id}, socket) do
    reload_entities(socket)
  end

  defp reload_entities(socket) do
    page = socket.assigns.current_page
    per_page = socket.assigns.per_page
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant

    query_params =
      %{
        "limit" => to_string(per_page),
        "offset" => to_string((page - 1) * per_page),
        "count" => "true"
      }
      |> maybe_put("type", socket.assigns.type_filter)
      |> maybe_put("id", if(socket.assigns.search != "", do: socket.assigns.search, else: nil))

    {:ok, entities, meta} = NGSI.query_entities(query_params, tenant || :all)
    {:ok, types} = NGSI.get_types()

    {:noreply,
     socket
     |> assign(:types, types)
     |> assign(:total_count, meta.total_count)
     |> stream(:entities, entities, reset: true)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    params = build_params(q, socket.assigns.type_filter)
    {:noreply, push_patch(socket, to: "/entities?#{URI.encode_query(params)}")}
  end

  def handle_event("filter-type", %{"type" => type}, socket) do
    type = if type == "", do: nil, else: type
    params = build_params(socket.assigns.search, type)
    {:noreply, push_patch(socket, to: "/entities?#{URI.encode_query(params)}")}
  end

  def handle_event("delete", %{"id" => entity_id}, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    {_graph_name, entity_tenant} = resolve_entity_tenant(entity_id, tenant)

    case NGSI.delete_entity(entity_id, entity_tenant) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Entity deleted")
         |> push_patch(to: "/entities")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete entity")}
    end
  end

  def handle_event("toggle-create-mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :create_mode, String.to_existing_atom(mode))}
  end

  def handle_event("add-attr", _, socket) do
    attrs =
      socket.assigns.create_attrs ++ [%{"name" => "", "attr_type" => "Property", "value" => ""}]

    {:noreply, assign(socket, :create_attrs, attrs)}
  end

  def handle_event("remove-attr", %{"index" => idx}, socket) do
    index = String.to_integer(idx)
    attrs = List.delete_at(socket.assigns.create_attrs, index)
    {:noreply, assign(socket, :create_attrs, attrs)}
  end

  def handle_event("create-entity", %{"entity" => params}, socket) do
    case socket.assigns.create_mode do
      :form ->
        create_from_form(params, socket)

      :json ->
        create_from_json(params, socket)
    end
  end

  defp create_from_form(%{"id" => id, "type" => type} = params, socket) do
    id = String.trim(id)
    type = String.trim(type)

    if id == "" or type == "" do
      {:noreply, put_flash(socket, :error, "Entity ID and Type are required")}
    else
      attrs =
        (params["attrs"] || %{})
        |> Enum.sort_by(fn {k, _v} -> k end)
        |> Enum.reduce(%{}, fn {_idx, attr}, acc ->
          name = String.trim(attr["name"] || "")
          attr_type = attr["attr_type"] || "Property"
          raw_value = attr["value"] || ""

          if name == "" do
            acc
          else
            case attr_type do
              "Property" ->
                Map.put(acc, name, %{"type" => "Property", "value" => parse_value(raw_value)})

              "Relationship" ->
                Map.put(acc, name, %{"type" => "Relationship", "object" => raw_value})

              "GeoProperty" ->
                geo = try_parse_json(raw_value, %{"type" => "Point", "coordinates" => [0, 0]})
                Map.put(acc, name, %{"type" => "GeoProperty", "value" => geo})

              _ ->
                acc
            end
          end
        end)

      entity = Map.merge(%{"id" => id, "type" => type}, attrs)
      do_create(entity, socket)
    end
  end

  defp create_from_json(%{"json" => json}, socket) do
    case Jason.decode(json) do
      {:ok, entity} when is_map(entity) ->
        do_create(entity, socket)

      {:ok, _} ->
        {:noreply, put_flash(socket, :error, "JSON must be an object, not an array")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON")}
    end
  end

  defp do_create(entity, socket) do
    tenant =
      case socket.assigns.current_scope do
        %{active_tenant: t} when is_binary(t) -> t
        _ -> nil
      end

    case NGSI.create_entity(entity, tenant) do
      {:ok, entity_id} ->
        {:ok, types} = NGSI.get_types()

        {:noreply,
         socket
         |> assign(:types, types)
         |> assign(:create_attrs, [])
         |> assign(:create_form, to_form(%{"id" => "", "type" => "", "json" => ""}, as: :entity))
         |> put_flash(:info, "Entity created: #{entity_id}")
         |> push_navigate(to: "/entities/#{URI.encode_www_form(entity_id)}")}

      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "Entity already exists")}

      {:error, :bad_request} ->
        {:noreply, put_flash(socket, :error, "Invalid entity data — id and type are required")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Create failed: #{inspect(reason)}")}
    end
  end

  defp parse_value(val) do
    str = String.trim(val)

    cond do
      str == "true" -> true
      str == "false" -> false
      str == "null" -> nil
      match?({_n, ""}, Integer.parse(str)) -> String.to_integer(str)
      match?({_n, ""}, Float.parse(str)) -> String.to_float(str)
      true -> str
    end
  end

  defp try_parse_json(str, default) do
    case Jason.decode(str) do
      {:ok, val} -> val
      _ -> default
    end
  end

  defp build_params(search, type_filter) do
    %{}
    |> maybe_put("q", if(search != "", do: search, else: nil))
    |> maybe_put("type", type_filter)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Derive tenant for an entity: use the active scope tenant if it's specific, otherwise look up from store.
  defp resolve_entity_tenant(_entity_id, tenant) when is_binary(tenant) do
    {nil, tenant}
  end

  defp resolve_entity_tenant(entity_id, _else) do
    graph_name = Store.find_graph_name_by_subject(entity_id) || entity_id

    tenant =
      if graph_name == entity_id,
        do: nil,
        else: String.replace_suffix(graph_name, ":#{entity_id}", "")

    {graph_name, tenant}
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp attr_count(entity) do
    entity
    |> Map.drop(["id", "type", "createdAt", "modifiedAt", "scope", "@context"])
    |> map_size()
  end

  defp type_badge_class(type) do
    colors = %{
      "Vehicle" => "badge-primary",
      "Sensor" => "badge-success",
      "Device" => "badge-secondary",
      "Building" => "badge-warning",
      "Room" => "badge-info"
    }

    Map.get(colors, type, "badge-neutral")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:entities} current_scope={@current_scope}>
      <%= if @live_action != :new do %>
        <div class="space-y-4">
          <%!-- Header --%>
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <h1 class="text-2xl font-bold tracking-tight heading-gradient">Entities</h1>
              <p class="text-sm opacity-50 mt-0.5">{@total_count} total entities</p>
            </div>
            <.link
              navigate="/entities/new"
              class="btn btn-sm bg-gradient-nb text-white border-nb gap-1.5"
            >
              <.icon name="hero-plus" class="size-4" /> New Entity
            </.link>
          </div>

          <%!-- Filters --%>
          <div class="flex flex-col sm:flex-row gap-2">
            <form phx-submit="search" class="flex-1">
              <label class="input input-sm input-bordered flex items-center gap-2 bg-base-200/50 w-full sm:max-w-sm">
                <.icon name="hero-magnifying-glass" class="size-4 opacity-40" />
                <input
                  type="text"
                  name="q"
                  value={@search}
                  placeholder="Search by entity ID..."
                  class="grow border-0 bg-transparent focus:outline-none text-sm"
                  phx-debounce="300"
                />
              </label>
            </form>
            <form phx-change="filter-type">
              <select name="type" class="select select-sm select-bordered bg-base-200/50 min-w-32">
                <option value="">All Types</option>
                <%= for t <- @types do %>
                  <option value={t} selected={@type_filter == t}>{t}</option>
                <% end %>
              </select>
            </form>
          </div>

          <%!-- Entity Table --%>
          <div class="card bg-base-200/50 border border-base-300/50 rounded-xl overflow-hidden">
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-xs opacity-50 border-base-300/50">
                    <th>Entity ID</th>
                    <th>Type</th>
                    <th class="hidden md:table-cell">Attributes</th>
                    <th class="hidden lg:table-cell">Created</th>
                    <th class="text-right">Actions</th>
                  </tr>
                </thead>
                <tbody id="entities-table" phx-update="stream">
                  <tr class="hidden only:table-row">
                    <td colspan="5" class="text-center py-10 opacity-40">
                      No entities found
                    </td>
                  </tr>
                  <tr
                    :for={{dom_id, entity} <- @streams.entities}
                    id={dom_id}
                    class="hover:bg-base-300/30 transition-colors border-base-300/30 group"
                  >
                    <td>
                      <.link
                        navigate={"/entities/#{URI.encode_www_form(entity["id"])}"}
                        class="font-mono text-xs hover:text-primary transition-colors"
                      >
                        {entity["id"]}
                      </.link>
                    </td>
                    <td>
                      <span class={["badge badge-sm badge-outline", type_badge_class(entity["type"])]}>
                        {entity["type"]}
                      </span>
                    </td>
                    <td class="hidden md:table-cell text-xs opacity-60">
                      {attr_count(entity)} attrs
                    </td>
                    <td class="hidden lg:table-cell text-xs opacity-50">
                      {format_time(entity["createdAt"])}
                    </td>
                    <td class="text-right">
                      <div class="flex justify-end gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <.link
                          navigate={"/charts?entity=#{URI.encode_www_form(entity["id"])}"}
                          class="btn btn-xs btn-ghost"
                          title="Charts"
                        >
                          <.icon name="hero-chart-bar" class="size-3.5" />
                        </.link>
                        <.link
                          navigate={"/entities/#{URI.encode_www_form(entity["id"])}"}
                          class="btn btn-xs btn-ghost"
                          title="View"
                        >
                          <.icon name="hero-eye" class="size-3.5" />
                        </.link>
                        <button
                          phx-click="delete"
                          phx-value-id={entity["id"]}
                          data-confirm="Delete this entity?"
                          class="btn btn-xs btn-ghost text-error"
                          title="Delete"
                        >
                          <.icon name="hero-trash" class="size-3.5" />
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <%!-- Pagination --%>
          <%= if @total_count > @per_page do %>
            <div class="flex justify-center">
              <div class="join">
                <%= if @current_page > 1 do %>
                  <.link
                    patch={
                      URI.encode(
                        "/entities?#{URI.encode_query(build_params(@search, @type_filter) |> Map.put("page", @current_page - 1))}"
                      )
                    }
                    class="join-item btn btn-sm"
                  >
                    <.icon name="hero-chevron-left" class="size-4" />
                  </.link>
                <% end %>
                <button class="join-item btn btn-sm btn-active">
                  Page {@current_page}
                </button>
                <%= if @current_page * @per_page < @total_count do %>
                  <.link
                    patch={
                      URI.encode(
                        "/entities?#{URI.encode_query(build_params(@search, @type_filter) |> Map.put("page", @current_page + 1))}"
                      )
                    }
                    class="join-item btn btn-sm"
                  >
                    <.icon name="hero-chevron-right" class="size-4" />
                  </.link>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Create Entity Page --%>
      <%= if @live_action == :new do %>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <%!-- Sidebar --%>
          <div class="lg:col-span-1 space-y-3">
            <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-4">
              <h3 class="text-xs font-semibold uppercase tracking-wider opacity-40 mb-3">
                Input Mode
              </h3>
              <div class="flex flex-col gap-1.5">
                <button
                  class={[
                    "btn btn-sm justify-start gap-2",
                    @create_mode == :form && "btn-primary btn-outline",
                    @create_mode != :form && "btn-ghost"
                  ]}
                  phx-click="toggle-create-mode"
                  phx-value-mode="form"
                >
                  <.icon name="hero-pencil-square" class="size-4" /> Form Builder
                </button>
                <button
                  class={[
                    "btn btn-sm justify-start gap-2",
                    @create_mode == :json && "btn-primary btn-outline",
                    @create_mode != :json && "btn-ghost"
                  ]}
                  phx-click="toggle-create-mode"
                  phx-value-mode="json"
                >
                  <.icon name="hero-code-bracket" class="size-4" /> Raw JSON
                </button>
              </div>
            </div>
            <div class="card bg-info/5 border border-info/20 rounded-xl p-4">
              <div class="flex gap-2">
                <.icon name="hero-information-circle" class="size-4 text-info shrink-0 mt-0.5" />
                <div class="text-xs opacity-70 space-y-1">
                  <p>
                    Every entity needs an <strong>id</strong>
                    (URN format) and a <strong>type</strong>.
                  </p>
                  <p>Attributes can be Properties, Relationships, or GeoProperties.</p>
                </div>
              </div>
            </div>
          </div>

          <%!-- Main form --%>
          <div class="lg:col-span-2">
            <.form for={@create_form} id="create-entity-form" phx-submit="create-entity">
              <div class="card bg-base-200/50 border border-base-300/50 rounded-xl overflow-hidden">
                <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-300/50 bg-base-200/30">
                  <div class="flex items-center gap-2">
                    <.icon name="hero-plus-circle" class="size-4 opacity-50" />
                    <span class="text-sm font-medium">New Entity</span>
                  </div>
                  <span class="badge badge-ghost badge-xs">
                    {if @create_mode == :form, do: "form", else: "json"}
                  </span>
                </div>
                <div class="p-5 space-y-4">
                  <%= if @create_mode == :form do %>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div>
                        <.input
                          field={@create_form[:id]}
                          label="Entity ID"
                          placeholder="urn:ngsi-ld:Type:id001"
                          required
                        />
                      </div>
                      <div>
                        <.input
                          field={@create_form[:type]}
                          label="Entity Type"
                          placeholder="e.g. Vehicle, Sensor"
                          required
                        />
                      </div>
                    </div>

                    <%!-- Dynamic attributes --%>
                    <div>
                      <div class="flex items-center justify-between mb-3">
                        <span class="text-xs font-semibold uppercase tracking-wider opacity-40">
                          Attributes
                        </span>
                        <button
                          type="button"
                          phx-click="add-attr"
                          class="btn btn-xs btn-outline btn-primary gap-1"
                        >
                          <.icon name="hero-plus" class="size-3" /> Add
                        </button>
                      </div>
                      <div class="space-y-3">
                        <%= for {attr, idx} <- Enum.with_index(@create_attrs) do %>
                          <div class="flex gap-3 items-start p-4 bg-base-300/30 rounded-lg border border-base-300/30 hover:border-primary/20 transition-colors">
                            <div class="flex items-center justify-center size-8 rounded-lg bg-base-200 text-xs font-bold opacity-40 shrink-0 mt-1">
                              {idx + 1}
                            </div>
                            <div class="flex-1 space-y-2">
                              <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                                <div>
                                  <label class="text-[10px] uppercase tracking-wider opacity-40 mb-1 block">
                                    Name
                                  </label>
                                  <input
                                    type="text"
                                    name={"entity[attrs][#{idx}][name]"}
                                    value={attr["name"]}
                                    placeholder="e.g. temperature"
                                    class="input input-sm w-full"
                                  />
                                </div>
                                <div>
                                  <label class="text-[10px] uppercase tracking-wider opacity-40 mb-1 block">
                                    Type
                                  </label>
                                  <select
                                    name={"entity[attrs][#{idx}][attr_type]"}
                                    class="select select-sm w-full"
                                  >
                                    <option
                                      value="Property"
                                      selected={attr["attr_type"] == "Property"}
                                    >
                                      Property
                                    </option>
                                    <option
                                      value="Relationship"
                                      selected={attr["attr_type"] == "Relationship"}
                                    >
                                      Relationship
                                    </option>
                                    <option
                                      value="GeoProperty"
                                      selected={attr["attr_type"] == "GeoProperty"}
                                    >
                                      GeoProperty
                                    </option>
                                  </select>
                                </div>
                              </div>
                              <div>
                                <label class="text-[10px] uppercase tracking-wider opacity-40 mb-1 block">
                                  Value
                                </label>
                                <input
                                  type="text"
                                  name={"entity[attrs][#{idx}][value]"}
                                  value={attr["value"]}
                                  placeholder={
                                    case attr["attr_type"] do
                                      "Relationship" -> "urn:ngsi-ld:Type:targetId"
                                      "GeoProperty" -> ~s({"type":"Point","coordinates":[0,0]})
                                      _ -> "Value (string, number, or boolean)"
                                    end
                                  }
                                  class="input input-sm w-full"
                                />
                              </div>
                            </div>
                            <button
                              type="button"
                              phx-click="remove-attr"
                              phx-value-index={idx}
                              class="btn btn-xs btn-ghost btn-square text-error/60 hover:text-error mt-1 shrink-0"
                            >
                              <.icon name="hero-x-mark" class="size-3.5" />
                            </button>
                          </div>
                        <% end %>
                        <button
                          type="button"
                          phx-click="add-attr"
                          class="w-full p-3 rounded-lg border-2 border-dashed border-base-300/60 hover:border-primary/40 text-sm opacity-50 hover:opacity-80 transition-all flex items-center justify-center gap-1.5"
                        >
                          <.icon name="hero-plus" class="size-4" /> Add attribute
                        </button>
                      </div>
                    </div>
                  <% else %>
                    <textarea
                      name="entity[json]"
                      id="create-entity-json"
                      placeholder={
                        ~s({\n  "id": "urn:ngsi-ld:Sensor:001",\n  "type": "Sensor",\n  "temperature": {\n    "type": "Property",\n    "value": 25.5\n  }\n})
                      }
                      class="w-full min-h-[50vh] bg-transparent font-mono text-xs p-4 border-0 focus:outline-none focus:ring-0 resize-y"
                    >{@create_form[:json].value}</textarea>
                  <% end %>
                </div>
              </div>
              <div class="flex items-center justify-between mt-4">
                <.link navigate="/entities" class="btn btn-sm btn-ghost gap-1">
                  <.icon name="hero-arrow-left" class="size-3.5" /> Back to entities
                </.link>
                <button type="submit" class="btn btn-sm btn-primary gap-1.5">
                  <.icon name="hero-plus" class="size-4" /> Create Entity
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp format_time(nil), do: "-"

  defp format_time(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%b %d, %H:%M")

      _ ->
        String.slice(ts, 0, 16)
    end
  end
end
