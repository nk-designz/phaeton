defmodule PhaetonWeb.MapLive do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI

  @impl true
  def mount(params, _session, socket) do
    focus_id = Map.get(params, "focus")
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant

    {:ok, entities, _meta} = NGSI.query_entities(%{"limit" => "10000"}, tenant || :all)
    markers = extract_markers(entities)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phaeton.PubSub, "ngsi:entity_changes")
    end

    socket =
      socket
      |> assign(:page_title, "Map")
      |> assign(:markers, markers)
      |> assign(:focus_id, focus_id)
      |> assign(:marker_count, length(markers))
      |> assign(:entity_count, length(Enum.uniq_by(markers, & &1.id)))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:entity_changed, _entity_id, _entity_data, _change_type}, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    {:ok, entities, _meta} = NGSI.query_entities(%{"limit" => "10000"}, tenant || :all)
    markers = extract_markers(entities)

    {:noreply,
     socket
     |> assign(:markers, markers)
     |> assign(:marker_count, length(markers))
     |> assign(:entity_count, length(Enum.uniq_by(markers, & &1.id)))
     |> push_event("update-markers", %{markers: markers})}
  end

  def handle_info({:entity_deleted, _entity_id}, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    {:ok, entities, _meta} = NGSI.query_entities(%{"limit" => "10000"}, tenant || :all)
    markers = extract_markers(entities)

    {:noreply,
     socket
     |> assign(:markers, markers)
     |> assign(:marker_count, length(markers))
     |> assign(:entity_count, length(Enum.uniq_by(markers, & &1.id)))
     |> push_event("update-markers", %{markers: markers})}
  end

  defp extract_markers(entities) do
    entities
    |> Enum.flat_map(fn entity ->
      entity
      |> Enum.filter(fn
        {_k, %{"type" => "GeoProperty", "value" => %{"coordinates" => [_lng, _lat | _]}}} ->
          true

        _ ->
          false
      end)
      |> Enum.map(fn {attr_name, geo} ->
        [lng, lat | _] = geo["value"]["coordinates"]

        %{
          id: entity["id"],
          type: entity["type"],
          attr: attr_name,
          lat: lat,
          lng: lng,
          label: short_id(entity["id"]),
          geo_type: geo["value"]["type"] || "Point"
        }
      end)
    end)
  end

  defp short_id(id), do: id |> String.split(":") |> List.last()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:map} current_scope={@current_scope}>
      <div class="flex flex-col h-[calc(100vh-8rem)]">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-3">
          <div>
            <h1 class="text-lg font-bold flex items-center gap-2 heading-gradient">
              <.icon name="hero-map" class="size-5 text-primary" /> Entity Map
            </h1>
            <p class="text-xs opacity-50 mt-0.5">
              {@entity_count} entities with {@marker_count} geo-locations
            </p>
          </div>
          <div class="flex gap-2 items-center">
            <button
              id="map-fit-btn"
              phx-click={
                Phoenix.LiveView.JS.dispatch("phx:map-fit-bounds",
                  to: "#leaflet-map-container"
                )
              }
              class="btn btn-sm btn-outline gap-1"
            >
              <.icon name="hero-arrows-pointing-out" class="size-4" /> Fit All
            </button>
          </div>
        </div>

        <%!-- Map Container --%>
        <div class="flex-1 card-glass overflow-hidden relative">
          <div
            id="leaflet-map-container"
            phx-hook=".LeafletMap"
            phx-update="ignore"
            data-markers={Jason.encode!(@markers)}
            data-focus={@focus_id}
            class="w-full h-full min-h-[400px]"
          >
          </div>

          <%!-- Empty state --%>
          <%= if @marker_count == 0 do %>
            <div class="absolute inset-0 flex items-center justify-center bg-base-200/80 backdrop-blur-sm z-[500]">
              <div class="text-center space-y-3">
                <.icon name="hero-map" class="size-12 opacity-20 mx-auto" />
                <p class="text-sm opacity-50">No entities with GeoProperty found</p>
                <.link navigate="/entities" class="btn btn-sm btn-primary btn-outline">
                  Browse Entities
                </.link>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".LeafletMap">
      const TILES = {
        dark: {
          url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
          attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a> &copy; <a href="https://carto.com/">CARTO</a>'
        },
        light: {
          url: "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
          attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a> &copy; <a href="https://carto.com/">CARTO</a>'
        }
      }

      function currentTheme() {
        return document.documentElement.getAttribute("data-theme") || "dark"
      }

      // Custom marker icon
      function createIcon(L, type) {
        const hue = Math.abs(hashCode(type)) % 360
        return L.divIcon({
          className: "leaflet-marker-custom",
          html: `<div style="background: oklch(60% 0.22 ${hue})" class="marker-dot"><div class="marker-pulse" style="border-color: oklch(60% 0.22 ${hue})"></div></div>`,
          iconSize: [24, 24],
          iconAnchor: [12, 12],
          popupAnchor: [0, -14]
        })
      }

      export default {
        mounted() {
          const L = window.L
          const el = this.el
          const markers = JSON.parse(el.dataset.markers || "[]")
          const focusId = el.dataset.focus || null

          this._L = L

          // Create map with no default zoom control (we add our own)
          this.map = L.map(el, {
            zoomControl: false,
            attributionControl: true
          }).setView([46.0, 2.0], 5)

          // Add zoom control on top-right
          L.control.zoom({ position: "topright" }).addTo(this.map)

          // Theme-aware tile layer
          const theme = currentTheme()
          const tile = TILES[theme] || TILES.dark
          this.tileLayer = L.tileLayer(tile.url, {
            attribution: tile.attribution,
            maxZoom: 19,
            subdomains: "abcd"
          }).addTo(this.map)

          // Listen for theme changes and swap tiles
          this._themeObserver = new MutationObserver(() => {
            const newTheme = currentTheme()
            const newTile = TILES[newTheme] || TILES.dark
            this.tileLayer.setUrl(newTile.url)
          })
          this._themeObserver.observe(document.documentElement, {
            attributes: true, attributeFilter: ["data-theme"]
          })

          // Custom marker icon
          const mkIcon = (type) => createIcon(L, type)

          // Add markers
          this.markerGroup = L.featureGroup()
          this.markerLookup = {}

          markers.forEach(m => {
            const icon = mkIcon(m.type)
            const marker = L.marker([m.lat, m.lng], { icon })
              .bindPopup(`
                <div class="map-popup-body">
                  <div class="map-popup-type">${escapeHtml(m.type)}</div>
                  <div class="map-popup-label">${escapeHtml(m.label)}</div>
                  <div class="map-popup-coords">${escapeHtml(m.attr)}: [${m.lng.toFixed(4)}, ${m.lat.toFixed(4)}]</div>
                  <a href="/entities/${encodeURIComponent(m.id)}"
                     class="map-popup-link"
                     data-phx-link="redirect"
                     data-phx-link-state="push">
                    View Entity →
                  </a>
                </div>
              `, { closeButton: true, className: "map-popup" })
              .addTo(this.markerGroup)

            if (!this.markerLookup[m.id]) this.markerLookup[m.id] = []
            this.markerLookup[m.id].push(marker)
          })

          this.markerGroup.addTo(this.map)

          // Fit bounds or focus
          if (focusId && this.markerLookup[focusId]) {
            const focusMarkers = this.markerLookup[focusId]
            if (focusMarkers.length === 1) {
              this.map.setView(focusMarkers[0].getLatLng(), 16)
              focusMarkers[0].openPopup()
            } else {
              const group = L.featureGroup(focusMarkers)
              this.map.fitBounds(group.getBounds().pad(0.2))
              focusMarkers[0].openPopup()
            }
          } else if (markers.length > 0) {
            this.map.fitBounds(this.markerGroup.getBounds().pad(0.1))
          }

          // Handle fit bounds event from button
          el.addEventListener("phx:map-fit-bounds", () => {
            if (markers.length > 0) {
              this.map.fitBounds(this.markerGroup.getBounds().pad(0.1))
            }
          })

          // Handle live marker updates
          this.handleEvent("update-markers", ({markers: newMarkers}) => {
            const L = this._L
            this.markerGroup.clearLayers()
            this.markerLookup = {}

            newMarkers.forEach(m => {
              const icon = createIcon(L, m.type)
              const marker = L.marker([m.lat, m.lng], { icon })
                .bindPopup(`
                  <div class="map-popup-body">
                    <div class="map-popup-type">${escapeHtml(m.type)}</div>
                    <div class="map-popup-label">${escapeHtml(m.label)}</div>
                    <div class="map-popup-coords">${escapeHtml(m.attr)}: [${m.lng.toFixed(4)}, ${m.lat.toFixed(4)}]</div>
                    <a href="/entities/${encodeURIComponent(m.id)}"
                       class="map-popup-link"
                       data-phx-link="redirect"
                       data-phx-link-state="push">
                      View Entity →
                    </a>
                  </div>
                `, { closeButton: true, className: "map-popup" })
                .addTo(this.markerGroup)

              if (!this.markerLookup[m.id]) this.markerLookup[m.id] = []
              this.markerLookup[m.id].push(marker)
            })
          })

          // Fix map sizing after container render
          setTimeout(() => this.map.invalidateSize(), 100)
        },

        destroyed() {
          if (this._themeObserver) {
            this._themeObserver.disconnect()
          }
          if (this.map) {
            this.map.remove()
            this.map = null
          }
        }
      }

      function hashCode(str) {
        let hash = 0
        for (let i = 0; i < str.length; i++) {
          hash = ((hash << 5) - hash) + str.charCodeAt(i)
          hash |= 0
        }
        return hash
      }

      function escapeHtml(text) {
        const div = document.createElement("div")
        div.textContent = text
        return div.innerHTML
      }
    </script>
    """
  end
end
