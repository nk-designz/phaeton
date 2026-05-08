defmodule PhaetonWeb.EntityLive.Show do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI
  alias Phaeton.Store
  alias Phaeton.NGSI.Temporal

  @impl true
  def mount(%{"id" => encoded_id}, _session, socket) do
    entity_id = URI.decode_www_form(encoded_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phaeton.PubSub, "ngsi:entity_changes")
    end

    {graph_name, tenant} = find_entity_context(entity_id)

    case NGSI.get_entity(entity_id, tenant) do
      {:ok, entity} ->
        triples = Store.get_triples_by_graph(graph_name)
        json_str = Jason.encode!(entity, pretty: true)

        # Extract relationships for mini-graph
        relationships =
          entity
          |> Enum.filter(fn
            {_k, %{"type" => "Relationship"}} -> true
            _ -> false
          end)
          |> Enum.map(fn {k, v} -> %{name: k, target: v["object"]} end)

        socket =
          socket
          |> assign(:page_title, short_id(entity_id))
          |> assign(:entity_id, entity_id)
          |> assign(:entity_tenant, tenant)
          |> assign(:graph_name, graph_name)
          |> assign(:entity, entity)
          |> assign(:json_str, json_str)
          |> assign(:triples, triples)
          |> assign(:relationships, relationships)
          |> assign(:has_temporal, has_temporal?(entity_id))
          |> assign(:active_tab, :json)
          |> assign(:edit_json, json_str)
          |> assign(:add_attrs, [%{"name" => "", "attr_type" => "Property", "value" => ""}])

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Entity not found: #{entity_id}")
         |> push_navigate(to: "/entities")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    page_title =
      case socket.assigns.live_action do
        :edit -> "Edit #{short_id(socket.assigns.entity_id)}"
        :new_attr -> "Add Attributes · #{short_id(socket.assigns.entity_id)}"
        _ -> short_id(socket.assigns.entity_id)
      end

    {:noreply, assign(socket, :page_title, page_title)}
  end

  @impl true
  def handle_info({:entity_changed, entity_id, _entity_data, _change_type}, socket) do
    if entity_id == socket.assigns.entity_id do
      case NGSI.get_entity(entity_id, socket.assigns.entity_tenant) do
        {:ok, entity} ->
          triples = Store.get_triples_by_graph(socket.assigns.graph_name)
          json_str = Jason.encode!(entity, pretty: true)

          relationships =
            entity
            |> Enum.filter(fn
              {_k, %{"type" => "Relationship"}} -> true
              _ -> false
            end)
            |> Enum.map(fn {k, v} -> %{name: k, target: v["object"]} end)

          {:noreply,
           socket
           |> assign(:entity, entity)
           |> assign(:json_str, json_str)
           |> assign(:triples, triples)
           |> assign(:relationships, relationships)
           |> assign(:has_temporal, has_temporal?(entity_id))
           |> assign(:edit_json, json_str)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:entity_deleted, entity_id}, socket) do
    if entity_id == socket.assigns.entity_id do
      {:noreply,
       socket
       |> put_flash(:error, "This entity was deleted")
       |> push_navigate(to: "/entities")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("delete", _, socket) do
    case NGSI.delete_entity(socket.assigns.entity_id, socket.assigns.entity_tenant) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Entity deleted")
         |> push_navigate(to: "/entities")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete entity")}
    end
  end

  def handle_event("update-entity-json", %{"entity" => %{"json" => json}}, socket) do
    case Jason.decode(json) do
      {:ok, fragment} when is_map(fragment) ->
        # Remove id/type — merge only attributes
        fragment = Map.drop(fragment, ["id", "type", "@context"])

        case NGSI.merge_entity(socket.assigns.entity_id, fragment, socket.assigns.entity_tenant) do
          :ok ->
            reload_entity(socket, "Entity updated")

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Update failed: #{inspect(reason)}")}
        end

      {:ok, _} ->
        {:noreply, put_flash(socket, :error, "JSON must be an object")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON")}
    end
  end

  def handle_event("add-attr-row", _, socket) do
    attrs =
      socket.assigns.add_attrs ++ [%{"name" => "", "attr_type" => "Property", "value" => ""}]

    {:noreply, assign(socket, :add_attrs, attrs)}
  end

  def handle_event("remove-attr-row", %{"index" => idx}, socket) do
    index = String.to_integer(idx)
    attrs = List.delete_at(socket.assigns.add_attrs, index)

    attrs =
      if attrs == [], do: [%{"name" => "", "attr_type" => "Property", "value" => ""}], else: attrs

    {:noreply, assign(socket, :add_attrs, attrs)}
  end

  def handle_event("append-attrs", %{"attrs" => raw_attrs}, socket) do
    fragment =
      raw_attrs
      |> Enum.sort_by(fn {k, _} -> k end)
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

    if fragment == %{} do
      {:noreply, put_flash(socket, :error, "No attributes to add")}
    else
      case NGSI.append_attrs(socket.assigns.entity_id, fragment, [], socket.assigns.entity_tenant) do
        :ok ->
          socket =
            assign(socket, :add_attrs, [%{"name" => "", "attr_type" => "Property", "value" => ""}])

          reload_entity(socket, "Attributes added")

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("delete-attr", %{"attr" => attr_name}, socket) do
    case NGSI.delete_attr(socket.assigns.entity_id, attr_name, socket.assigns.entity_tenant) do
      :ok ->
        reload_entity(socket, "Attribute '#{attr_name}' deleted")

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete attribute: #{inspect(reason)}")}
    end
  end

  defp reload_entity(socket, flash_msg) do
    entity_id = socket.assigns.entity_id

    case NGSI.get_entity(entity_id, socket.assigns.entity_tenant) do
      {:ok, entity} ->
        triples = Store.get_triples_by_graph(socket.assigns.graph_name)
        json_str = Jason.encode!(entity, pretty: true)

        relationships =
          entity
          |> Enum.filter(fn
            {_k, %{"type" => "Relationship"}} -> true
            _ -> false
          end)
          |> Enum.map(fn {k, v} -> %{name: k, target: v["object"]} end)

        {:noreply,
         socket
         |> assign(:entity, entity)
         |> assign(:json_str, json_str)
         |> assign(:edit_json, json_str)
         |> assign(:triples, triples)
         |> assign(:relationships, relationships)
         |> put_flash(:info, flash_msg)
         |> push_patch(to: "/entities/#{URI.encode_www_form(entity_id)}")}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Entity no longer exists")
         |> push_navigate(to: "/entities")}
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

  defp short_id(id), do: id |> String.split(":") |> List.last()

  # Resolves which tenant (and graph_name) an entity lives in by looking up its subject in the store.
  # Returns {graph_name, tenant} — tenant is nil for the default (un-tenanted) graph.
  defp find_entity_context(entity_id) do
    graph_name = Store.find_graph_name_by_subject(entity_id) || entity_id

    tenant =
      if graph_name == entity_id do
        nil
      else
        String.replace_suffix(graph_name, ":#{entity_id}", "")
      end

    {graph_name, tenant}
  end

  defp has_temporal?(entity_id) do
    case Temporal.retrieve_temporal(entity_id) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # Semantic icon based on attribute name, unitCode, then type fallback
  defp attr_icon(name, attr) do
    name_down = String.downcase(name)
    unit = (attr["unitCode"] || "") |> String.upcase()

    cond do
      # Temperature / thermal
      unit in ["CEL", "FAH", "KEL"] ->
        "hero-fire"

      String.contains?(name_down, "temp") ->
        "hero-fire"

      # Humidity / moisture
      String.contains?(name_down, "humid") or String.contains?(name_down, "moisture") ->
        "hero-beaker"

      # Energy / power / wattage
      unit in ["KWH", "WTT", "MWH", "JOU"] ->
        "hero-bolt"

      String.contains?(name_down, "energy") or String.contains?(name_down, "power") or
          String.contains?(name_down, "watt") ->
        "hero-bolt"

      # Light / PPFD / lux
      unit in ["LUX", "UMOL"] ->
        "hero-sun"

      String.contains?(name_down, "light") or String.contains?(name_down, "ppfd") or
        String.contains?(name_down, "intensity") or String.contains?(name_down, "spectrum") ->
        "hero-sun"

      # Battery / charge
      String.contains?(name_down, "battery") or String.contains?(name_down, "charge") ->
        "hero-battery-50"

      # Water / flow / irrigation / pH / EC
      unit in ["LTR", "MLT", "GAL", "MQS"] ->
        "hero-beaker"

      String.contains?(name_down, "water") or String.contains?(name_down, "flow") or
        String.contains?(name_down, "irrigat") or name_down == "ph" or name_down == "ec" ->
        "hero-beaker"

      # CO2 / air / ventilation
      String.contains?(name_down, "co2") or String.contains?(name_down, "air") or
        String.contains?(name_down, "fan") or String.contains?(name_down, "ventil") ->
        "hero-cloud"

      # Speed / velocity
      String.contains?(name_down, "speed") or String.contains?(name_down, "velocity") ->
        "hero-forward"

      # Location / position / coordinates
      attr["type"] == "GeoProperty" or String.contains?(name_down, "location") or
          String.contains?(name_down, "position") ->
        "hero-map-pin"

      # Status / state / mode
      String.contains?(name_down, "status") or String.contains?(name_down, "state") or
        String.contains?(name_down, "mode") or String.contains?(name_down, "enabled") ->
        "hero-signal"

      # Name / label / brand
      String.contains?(name_down, "name") or String.contains?(name_down, "brand") or
          String.contains?(name_down, "label") ->
        "hero-tag"

      # Count / quantity / number
      String.contains?(name_down, "count") or String.contains?(name_down, "quantity") or
          String.contains?(name_down, "total") ->
        "hero-calculator"

      # Time / date / schedule
      String.contains?(name_down, "time") or String.contains?(name_down, "date") or
        String.contains?(name_down, "since") or String.contains?(name_down, "period") or
        String.contains?(name_down, "schedule") or String.contains?(name_down, "maintenance") ->
        "hero-clock"

      # Health / score / accuracy
      String.contains?(name_down, "health") or String.contains?(name_down, "score") or
        String.contains?(name_down, "accuracy") or String.contains?(name_down, "quality") ->
        "hero-heart"

      # Growth / plant / harvest / stage
      String.contains?(name_down, "growth") or String.contains?(name_down, "plant") or
        String.contains?(name_down, "harvest") or String.contains?(name_down, "stage") or
          String.contains?(name_down, "depth") ->
        "hero-sparkles"

      # Severity / alert / threshold
      String.contains?(name_down, "severity") or String.contains?(name_down, "alert") or
          String.contains?(name_down, "threshold") ->
        "hero-exclamation-triangle"

      # Nutrient / fertilizer / concentration / dosing
      String.contains?(name_down, "nutri") or String.contains?(name_down, "fertil") or
        String.contains?(name_down, "concentr") or String.contains?(name_down, "dos") ->
        "hero-eyedropper"

      # Color
      String.contains?(name_down, "color") or String.contains?(name_down, "colour") ->
        "hero-swatch"

      # Relationships
      attr["type"] == "Relationship" ->
        "hero-link"

      # Language
      attr["type"] == "LanguageProperty" ->
        "hero-globe-alt"

      # Default property
      true ->
        "hero-cube"
    end
  end

  defp attr_color(name, attr) do
    name_down = String.downcase(name)
    unit = (attr["unitCode"] || "") |> String.upcase()

    cond do
      unit in ["CEL", "FAH", "KEL"] or String.contains?(name_down, "temp") ->
        "text-error"

      String.contains?(name_down, "humid") or String.contains?(name_down, "moisture") ->
        "text-info"

      unit in ["KWH", "WTT", "MWH"] or String.contains?(name_down, "energy") or
          String.contains?(name_down, "power") ->
        "text-warning"

      unit in ["LUX", "UMOL"] or String.contains?(name_down, "light") or
          String.contains?(name_down, "ppfd") ->
        "text-warning"

      String.contains?(name_down, "battery") ->
        "text-success"

      String.contains?(name_down, "water") or String.contains?(name_down, "flow") or
        name_down == "ph" or name_down == "ec" ->
        "text-info"

      String.contains?(name_down, "co2") or String.contains?(name_down, "air") ->
        "text-secondary"

      String.contains?(name_down, "health") or String.contains?(name_down, "score") ->
        "text-success"

      String.contains?(name_down, "severity") or String.contains?(name_down, "alert") ->
        "text-error"

      attr["type"] == "Relationship" ->
        "text-primary"

      attr["type"] == "GeoProperty" ->
        "text-success"

      attr["type"] == "LanguageProperty" ->
        "text-warning"

      true ->
        "text-info"
    end
  end

  defp format_value(val) when is_map(val), do: Jason.encode!(val)
  defp format_value(val) when is_list(val), do: Jason.encode!(val)
  defp format_value(val), do: to_string(val)

  defp compact_iri(iri) do
    cond do
      String.starts_with?(iri, "https://uri.etsi.org/ngsi-ld/") ->
        String.replace_prefix(iri, "https://uri.etsi.org/ngsi-ld/", "ngsi-ld:")

      String.starts_with?(iri, "http://www.w3.org/1999/02/22-rdf-syntax-ns#") ->
        String.replace_prefix(iri, "http://www.w3.org/1999/02/22-rdf-syntax-ns#", "rdf:")

      String.starts_with?(iri, "http://www.w3.org/2001/XMLSchema#") ->
        String.replace_prefix(iri, "http://www.w3.org/2001/XMLSchema#", "xsd:")

      true ->
        iri
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:entities} current_scope={@current_scope}>
      <div class="space-y-4">
        <%!-- Breadcrumb --%>
        <div class="text-sm breadcrumbs opacity-60 py-0">
          <ul>
            <li><.link navigate="/entities">Entities</.link></li>
            <li class="font-medium">{short_id(@entity_id)}</li>
          </ul>
        </div>

        <%= if @live_action == :show do %>
          <%!-- Entity Header --%>
          <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-5">
            <div class="flex flex-col sm:flex-row sm:items-start gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <span class="badge badge-primary badge-outline badge-sm">{@entity["type"]}</span>
                </div>
                <div class="flex items-center gap-2">
                  <h1 class="text-lg font-bold font-mono break-all">{@entity_id}</h1>
                  <button
                    id="copy-entity-id"
                    phx-hook=".CopyToClipboard"
                    data-value={@entity_id}
                    class="btn btn-xs btn-ghost btn-square opacity-40 hover:opacity-100 transition-opacity shrink-0"
                    title="Copy entity ID"
                  >
                    <.icon name="hero-clipboard-document" class="size-4" />
                  </button>
                </div>
                <div class="flex flex-wrap gap-x-4 gap-y-1 mt-2 text-xs opacity-50">
                  <%= if @entity["createdAt"] do %>
                    <span class="flex items-center gap-1">
                      <.icon name="hero-clock" class="size-3" /> Created: {@entity["createdAt"]}
                    </span>
                  <% end %>
                  <%= if @entity["modifiedAt"] do %>
                    <span class="flex items-center gap-1">
                      <.icon name="hero-pencil" class="size-3" /> Modified: {@entity["modifiedAt"]}
                    </span>
                  <% end %>
                </div>
              </div>
              <div class="flex gap-2 flex-wrap">
                <.link
                  patch={"/entities/#{URI.encode_www_form(@entity_id)}/edit"}
                  class="btn btn-sm btn-primary btn-outline gap-1"
                >
                  <.icon name="hero-pencil-square" class="size-4" /> Edit
                </.link>
                <.link
                  patch={"/entities/#{URI.encode_www_form(@entity_id)}/attrs/new"}
                  class="btn btn-sm btn-outline gap-1"
                >
                  <.icon name="hero-plus" class="size-4" /> Add Attribute
                </.link>
                <.link navigate="/graph" class="btn btn-sm btn-outline gap-1">
                  <.icon name="hero-share" class="size-4" /> Graph
                </.link>
                <.link
                  navigate={"/map?focus=#{URI.encode_www_form(@entity_id)}"}
                  class="btn btn-sm btn-outline gap-1"
                >
                  <.icon name="hero-map" class="size-4" /> Map
                </.link>
                <.link
                  navigate={"/charts?entity=#{URI.encode_www_form(@entity_id)}"}
                  class={["btn btn-sm btn-outline gap-1", !@has_temporal && "btn-disabled opacity-40"]}
                >
                  <.icon name="hero-chart-bar" class="size-4" /> Charts
                </.link>
                <button
                  phx-click="delete"
                  data-confirm="Delete this entity permanently?"
                  class="btn btn-sm btn-error btn-outline gap-1"
                >
                  <.icon name="hero-trash" class="size-4" /> Delete
                </button>
              </div>
            </div>
          </div>

          <%!-- Attributes Cards --%>
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
            <%= for {attr_name, attr_value} <- @entity,
                  is_map(attr_value) and Map.has_key?(attr_value, "type"),
                  attr_name not in ["id", "type", "createdAt", "modifiedAt", "@context"] do %>
              <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-4 hover:border-primary/30 transition-colors group/attr">
                <div class="flex items-center gap-2 mb-2">
                  <.icon
                    name={attr_icon(attr_name, attr_value)}
                    class={["size-4", attr_color(attr_name, attr_value)]}
                  />
                  <span class="font-semibold text-sm truncate flex-1">{attr_name}</span>
                  <span class="badge badge-xs opacity-50">{attr_value["type"]}</span>
                  <button
                    phx-click="delete-attr"
                    phx-value-attr={attr_name}
                    data-confirm={"Delete attribute '#{attr_name}'?"}
                    class="btn btn-xs btn-ghost btn-square text-error opacity-0 group-hover/attr:opacity-100 transition-opacity"
                    title="Delete attribute"
                  >
                    <.icon name="hero-x-mark" class="size-3.5" />
                  </button>
                </div>
                <div class="text-sm opacity-80 break-all">
                  <%= cond do %>
                    <% attr_value["type"] == "GeoProperty" and is_map(attr_value["value"]) -> %>
                      <span class="font-mono text-xs">{format_value(attr_value["value"])}</span>
                      <.link
                        navigate={"/map?focus=#{URI.encode_www_form(@entity_id)}"}
                        class="inline-flex items-center gap-1 text-xs text-primary hover:underline mt-1"
                      >
                        <.icon name="hero-map" class="size-3" /> View on Map
                      </.link>
                    <% Map.has_key?(attr_value, "value") -> %>
                      <span class="font-mono text-xs">{format_value(attr_value["value"])}</span>
                    <% Map.has_key?(attr_value, "object") -> %>
                      <.link
                        navigate={"/entities/#{URI.encode_www_form(attr_value["object"])}"}
                        class="text-primary hover:underline font-mono text-xs"
                      >
                        {attr_value["object"]}
                      </.link>
                    <% Map.has_key?(attr_value, "languageMap") -> %>
                      <div class="space-y-0.5">
                        <%= for {lang, text} <- attr_value["languageMap"] do %>
                          <div class="text-xs">
                            <span class="badge badge-xs">{lang}</span> {text}
                          </div>
                        <% end %>
                      </div>
                    <% true -> %>
                      <span class="opacity-40 text-xs">—</span>
                  <% end %>
                </div>
                <%!-- Metadata --%>
                <div class="flex flex-wrap items-center gap-x-3 gap-y-0.5 mt-2">
                  <%= if attr_value["observedAt"] do %>
                    <span class="text-[10px] opacity-40 flex items-center gap-0.5">
                      <.icon name="hero-clock" class="size-2.5" />
                      {attr_value["observedAt"]}
                    </span>
                    <%= if @has_temporal do %>
                      <.link
                        navigate={"/charts?entity=#{URI.encode_www_form(@entity_id)}&attr=#{URI.encode_www_form(attr_name)}"}
                        class="text-[10px] text-primary hover:underline flex items-center gap-0.5"
                      >
                        <.icon name="hero-chart-bar" class="size-2.5" /> History
                      </.link>
                    <% end %>
                  <% end %>
                  <%= if attr_value["unitCode"] do %>
                    <span class="text-[10px] opacity-40">{attr_value["unitCode"]}</span>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Relationships Quick View --%>
          <%= if @relationships != [] do %>
            <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-5">
              <h2 class="font-semibold text-sm mb-3 flex items-center gap-2">
                <.icon name="hero-link" class="size-4 text-primary" /> Relationships
              </h2>
              <div class="flex flex-wrap gap-2">
                <%= for rel <- @relationships do %>
                  <.link
                    navigate={"/entities/#{URI.encode_www_form(rel.target)}"}
                    class="btn btn-sm btn-outline gap-1.5 hover:btn-primary transition-all"
                  >
                    <span class="text-xs opacity-60">{rel.name}</span>
                    <.icon name="hero-arrow-right" class="size-3" />
                    <span class="font-mono text-xs">{short_id(rel.target)}</span>
                  </.link>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Data Tabs --%>
          <div class="card bg-base-200/50 border border-base-300/50 rounded-xl overflow-hidden">
            <div role="tablist" class="tabs tabs-bordered px-4 pt-2">
              <button
                role="tab"
                class={["tab tab-sm gap-1.5", @active_tab == :json && "tab-active"]}
                phx-click="switch-tab"
                phx-value-tab="json"
              >
                <.icon name="hero-code-bracket" class="size-3.5" /> JSON-LD
              </button>
              <button
                role="tab"
                class={["tab tab-sm gap-1.5", @active_tab == :triples && "tab-active"]}
                phx-click="switch-tab"
                phx-value-tab="triples"
              >
                <.icon name="hero-table-cells" class="size-3.5" /> RDF Triples
                <span class="badge badge-xs opacity-50">{length(@triples)}</span>
              </button>
            </div>

            <div class="p-4">
              <%!-- JSON Tab --%>
              <div class={[@active_tab != :json && "hidden"]}>
                <div class="bg-base-300/50 rounded-lg p-4 overflow-x-auto max-h-[500px] overflow-y-auto">
                  <pre id="json-view" class="json-view" phx-hook=".JsonHighlight" phx-update="ignore">{@json_str}</pre>
                </div>
              </div>

              <%!-- Triples Tab --%>
              <div class={[@active_tab != :triples && "hidden"]}>
                <div class="overflow-x-auto max-h-[500px] overflow-y-auto">
                  <table class="table table-xs table-pin-rows">
                    <thead>
                      <tr class="text-xs opacity-50 border-base-300/50">
                        <th>Subject</th>
                        <th>Predicate</th>
                        <th>Object</th>
                        <th>Type</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for triple <- @triples do %>
                        <tr class="hover:bg-base-300/30 transition-colors border-base-300/30">
                          <td class="font-mono text-xs max-w-32 truncate" title={triple.subject}>
                            {compact_iri(triple.subject)}
                          </td>
                          <td
                            class="font-mono text-xs max-w-40 truncate text-primary"
                            title={triple.predicate}
                          >
                            {compact_iri(triple.predicate)}
                          </td>
                          <td class="font-mono text-xs max-w-48 truncate" title={triple.object_value}>
                            <%= if triple.object_type == "iri" do %>
                              <span class="text-info">{compact_iri(triple.object_value)}</span>
                            <% else %>
                              <span class="opacity-80">
                                {String.slice(triple.object_value, 0, 60)}
                              </span>
                            <% end %>
                          </td>
                          <td>
                            <span class={[
                              "badge badge-xs",
                              triple.object_type == "iri" && "badge-info badge-outline",
                              triple.object_type == "literal" && "badge-ghost",
                              triple.object_type == "blank_node" && "badge-warning badge-outline"
                            ]}>
                              {triple.object_type}
                            </span>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Edit Entity Page --%>
      <%= if @live_action == :edit do %>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <%!-- Sidebar: Entity context --%>
          <div class="lg:col-span-1 space-y-3">
            <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-4">
              <h3 class="text-xs font-semibold uppercase tracking-wider opacity-40 mb-3">Entity</h3>
              <div class="space-y-2">
                <div>
                  <span class="text-[10px] uppercase tracking-wider opacity-40">Type</span>
                  <div class="mt-0.5">
                    <span class="badge badge-primary badge-outline badge-sm">{@entity["type"]}</span>
                  </div>
                </div>
                <div>
                  <span class="text-[10px] uppercase tracking-wider opacity-40">ID</span>
                  <p class="font-mono text-xs break-all mt-0.5 opacity-80">{@entity_id}</p>
                </div>
              </div>
            </div>
            <div class="card bg-info/5 border border-info/20 rounded-xl p-4">
              <div class="flex gap-2">
                <.icon name="hero-information-circle" class="size-4 text-info shrink-0 mt-0.5" />
                <div class="text-xs opacity-70 space-y-1">
                  <p>
                    Edit the JSON to modify attributes. This sends a <strong>merge patch</strong>.
                  </p>
                  <p>
                    Changes to <code class="text-[10px] bg-base-300/50 px-1 rounded">id</code>
                    and <code class="text-[10px] bg-base-300/50 px-1 rounded">type</code>
                    are ignored.
                  </p>
                </div>
              </div>
            </div>
          </div>

          <%!-- Main: Editor --%>
          <div class="lg:col-span-2">
            <.form
              for={to_form(%{"json" => @edit_json}, as: :entity)}
              id="edit-entity-form"
              phx-submit="update-entity-json"
            >
              <div class="card bg-base-200/50 border border-base-300/50 rounded-xl overflow-hidden">
                <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-300/50 bg-base-200/30">
                  <div class="flex items-center gap-2">
                    <.icon name="hero-code-bracket" class="size-4 opacity-50" />
                    <span class="text-sm font-medium">JSON Merge Patch</span>
                  </div>
                  <span class="badge badge-ghost badge-xs">application/merge-patch+json</span>
                </div>
                <div class="p-0">
                  <textarea
                    name="entity[json]"
                    id="edit-entity-json"
                    class="w-full min-h-[60vh] bg-transparent font-mono text-xs p-4 border-0 focus:outline-none focus:ring-0 resize-y"
                  >{@edit_json}</textarea>
                </div>
              </div>
              <div class="flex items-center justify-between mt-4">
                <.link
                  patch={"/entities/#{URI.encode_www_form(@entity_id)}"}
                  class="btn btn-sm btn-ghost gap-1"
                >
                  <.icon name="hero-arrow-left" class="size-3.5" /> Back to entity
                </.link>
                <button type="submit" class="btn btn-sm btn-primary gap-1.5">
                  <.icon name="hero-check" class="size-4" /> Save Changes
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- Add Attribute Page --%>
      <%= if @live_action == :new_attr do %>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <%!-- Sidebar: Entity context + existing attrs --%>
          <div class="lg:col-span-1 space-y-3">
            <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-4">
              <h3 class="text-xs font-semibold uppercase tracking-wider opacity-40 mb-3">Entity</h3>
              <div class="space-y-2">
                <div>
                  <span class="text-[10px] uppercase tracking-wider opacity-40">Type</span>
                  <div class="mt-0.5">
                    <span class="badge badge-primary badge-outline badge-sm">{@entity["type"]}</span>
                  </div>
                </div>
                <div>
                  <span class="text-[10px] uppercase tracking-wider opacity-40">ID</span>
                  <p class="font-mono text-xs break-all mt-0.5 opacity-80">{@entity_id}</p>
                </div>
              </div>
            </div>
            <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-4">
              <h3 class="text-xs font-semibold uppercase tracking-wider opacity-40 mb-3">
                Existing Attributes
              </h3>
              <div class="flex flex-wrap gap-1">
                <%= for {attr_name, attr_value} <- @entity,
                        is_map(attr_value) and Map.has_key?(attr_value, "type"),
                        attr_name not in ["id", "type", "createdAt", "modifiedAt", "@context"] do %>
                  <span class="badge badge-sm badge-ghost gap-1">
                    <.icon
                      name={attr_icon(attr_name, attr_value)}
                      class={["size-3", attr_color(attr_name, attr_value)]}
                    />
                    {attr_name}
                  </span>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Main: Attribute form --%>
          <div class="lg:col-span-2">
            <form id="add-attr-form" phx-submit="append-attrs">
              <div class="card bg-base-200/50 border border-base-300/50 rounded-xl overflow-hidden">
                <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-300/50 bg-base-200/30">
                  <div class="flex items-center gap-2">
                    <.icon name="hero-plus-circle" class="size-4 opacity-50" />
                    <span class="text-sm font-medium">New Attributes</span>
                  </div>
                  <span class="badge badge-ghost badge-xs">{length(@add_attrs)} attribute(s)</span>
                </div>
                <div class="p-4 space-y-3">
                  <%= for {attr, idx} <- Enum.with_index(@add_attrs) do %>
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
                              name={"attrs[#{idx}][name]"}
                              value={attr["name"]}
                              placeholder="e.g. temperature"
                              class="input input-sm w-full"
                            />
                          </div>
                          <div>
                            <label class="text-[10px] uppercase tracking-wider opacity-40 mb-1 block">
                              Type
                            </label>
                            <select name={"attrs[#{idx}][attr_type]"} class="select select-sm w-full">
                              <option value="Property" selected={attr["attr_type"] == "Property"}>
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
                            name={"attrs[#{idx}][value]"}
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
                        phx-click="remove-attr-row"
                        phx-value-index={idx}
                        class="btn btn-xs btn-ghost btn-square text-error/60 hover:text-error mt-1 shrink-0"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </div>
                  <% end %>
                  <button
                    type="button"
                    phx-click="add-attr-row"
                    class="w-full p-3 rounded-lg border-2 border-dashed border-base-300/60 hover:border-primary/40 text-sm opacity-50 hover:opacity-80 transition-all flex items-center justify-center gap-1.5"
                  >
                    <.icon name="hero-plus" class="size-4" /> Add another attribute
                  </button>
                </div>
              </div>
              <div class="flex items-center justify-between mt-4">
                <.link
                  patch={"/entities/#{URI.encode_www_form(@entity_id)}"}
                  class="btn btn-sm btn-ghost gap-1"
                >
                  <.icon name="hero-arrow-left" class="size-3.5" /> Back to entity
                </.link>
                <button type="submit" class="btn btn-sm btn-primary gap-1.5">
                  <.icon name="hero-plus" class="size-4" /> Append Attributes
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            const value = this.el.dataset.value
            navigator.clipboard.writeText(value).then(() => {
              const icon = this.el.querySelector("[class*='hero-']")
              if (icon) {
                icon.className = icon.className.replace("hero-clipboard-document", "hero-check")
                setTimeout(() => {
                  icon.className = icon.className.replace("hero-check", "hero-clipboard-document")
                }, 1500)
              }
            })
          })
        }
      }
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".JsonHighlight">
      export default {
        mounted() {
          this.highlight()
        },
        highlight() {
          const raw = this.el.textContent
          try {
            const obj = JSON.parse(raw)
            this.el.innerHTML = this.syntaxHighlight(JSON.stringify(obj, null, 2))
          } catch(e) {}
        },
        syntaxHighlight(json) {
          return json.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(
              /("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,
              (match) => {
                let cls = 'json-number'
                if (/^"/.test(match)) {
                  cls = /:$/.test(match) ? 'json-key' : 'json-string'
                } else if (/true|false/.test(match)) {
                  cls = 'json-bool'
                } else if (/null/.test(match)) {
                  cls = 'json-null'
                }
                return '<span class="' + cls + '">' + match + '</span>'
              }
            )
        }
      }
    </script>
    """
  end
end
