defmodule PhaetonWeb.GraphLive do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    graph_data = NGSI.get_relationship_graph(tenant || :all)

    type_colors =
      graph_data.nodes
      |> Enum.map(& &1.type)
      |> Enum.uniq()
      |> Enum.with_index()
      |> Enum.map(fn {type, idx} ->
        palette = [
          {"#3b82f6", "bg-blue-500"},
          {"#22c55e", "bg-green-500"},
          {"#a855f7", "bg-purple-500"},
          {"#f97316", "bg-orange-500"},
          {"#ec4899", "bg-pink-500"},
          {"#06b6d4", "bg-cyan-500"},
          {"#eab308", "bg-yellow-500"},
          {"#ef4444", "bg-red-500"}
        ]

        {hex, tw} = Enum.at(palette, rem(idx, length(palette)))
        {type, hex, tw}
      end)

    color_map = Enum.into(type_colors, %{}, fn {type, hex, _} -> {type, hex} end)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phaeton.PubSub, "ngsi:entity_changes")
    end

    socket =
      socket
      |> assign(:page_title, "Graph Explorer")
      |> assign(:node_count, length(graph_data.nodes))
      |> assign(:edge_count, length(graph_data.edges))
      |> assign(:type_colors, type_colors)
      |> assign(:search, "")
      |> assign(:hidden_types, [])
      |> assign(:graph_data, %{
        nodes: graph_data.nodes,
        edges: graph_data.edges,
        colors: color_map
      })

    {:ok, socket}
  end

  @impl true
  def handle_info({:entity_changed, _entity_id, _entity_data, _change_type}, socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    graph_data = NGSI.get_relationship_graph(tenant || :all)

    {:noreply,
     socket
     |> assign(:node_count, length(graph_data.nodes))
     |> assign(:edge_count, length(graph_data.edges))}
  end

  def handle_info({:entity_deleted, _entity_id}, socket) do
    {:noreply, refresh_graph(socket)}
  end

  defp refresh_graph(socket) do
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    graph_data = NGSI.get_relationship_graph(tenant || :all)
    color_map = Enum.into(socket.assigns.type_colors, %{}, fn {type, hex, _} -> {type, hex} end)

    socket
    |> assign(:node_count, length(graph_data.nodes))
    |> assign(:edge_count, length(graph_data.edges))
    |> assign(:graph_data, %{
      nodes: graph_data.nodes,
      edges: graph_data.edges,
      colors: color_map
    })
    |> push_event("graph-data", %{
      nodes: graph_data.nodes,
      edges: graph_data.edges,
      colors: color_map
    })
  end

  @impl true
  def handle_event("refresh", _, socket) do
    graph_data = NGSI.get_relationship_graph()
    color_map = Enum.into(socket.assigns.type_colors, %{}, fn {type, hex, _} -> {type, hex} end)

    socket =
      socket
      |> assign(:node_count, length(graph_data.nodes))
      |> assign(:edge_count, length(graph_data.edges))
      |> assign(:graph_data, %{
        nodes: graph_data.nodes,
        edges: graph_data.edges,
        colors: color_map
      })
      |> push_event("graph-data", %{
        nodes: graph_data.nodes,
        edges: graph_data.edges,
        colors: color_map
      })

    {:noreply, socket}
  end

  def handle_event("node-click", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: "/entities/#{URI.encode_www_form(id)}")}
  end

  def handle_event("search-graph", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(:search, q)
     |> push_event("graph-search", %{query: q})}
  end

  def handle_event("toggle-type", %{"type" => type}, socket) do
    hidden = socket.assigns.hidden_types

    hidden =
      if type in hidden,
        do: List.delete(hidden, type),
        else: [type | hidden]

    {:noreply,
     socket
     |> assign(:hidden_types, hidden)
     |> push_event("graph-filter", %{hidden_types: hidden})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:graph} current_scope={@current_scope}>
      <div class="space-y-4">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold tracking-tight heading-gradient">Graph Explorer</h1>
            <p class="text-sm opacity-50 mt-0.5">{@node_count} nodes · {@edge_count} relationships</p>
          </div>
          <div class="flex items-center gap-2">
            <form phx-change="search-graph" class="flex-shrink-0">
              <label class="input input-sm input-bordered flex items-center gap-2 bg-base-200/50 w-52">
                <.icon name="hero-magnifying-glass" class="size-3.5 opacity-40" />
                <input
                  type="text"
                  name="q"
                  value={@search}
                  placeholder="Search nodes..."
                  class="grow border-0 bg-transparent focus:outline-none text-xs"
                  phx-debounce="200"
                />
              </label>
            </form>
            <button phx-click="refresh" class="btn btn-sm btn-ghost gap-1.5">
              <.icon name="hero-arrow-path" class="size-4" /> Refresh
            </button>
          </div>
        </div>

        <%!-- Legend (clickable type filters) --%>
        <%= if @type_colors != [] do %>
          <div class="flex flex-wrap gap-1.5">
            <%= for {type, _hex, tw_class} <- @type_colors do %>
              <button
                phx-click="toggle-type"
                phx-value-type={type}
                class={[
                  "flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium transition-all cursor-pointer",
                  if(type in @hidden_types,
                    do: "bg-base-200/30 border-base-300/30 opacity-40 line-through",
                    else: "bg-base-200 border-base-300/50 hover:border-primary/30"
                  )
                ]}
              >
                <span class={[
                  "w-2.5 h-2.5 rounded-full transition-opacity",
                  tw_class,
                  type in @hidden_types && "opacity-30"
                ]}>
                </span>
                {type}
              </button>
            <% end %>
          </div>
        <% end %>

        <%!-- Graph Container --%>
        <div
          id="graph-container"
          phx-hook=".ForceGraph"
          phx-update="ignore"
          class="graph-container card-glass overflow-hidden relative"
          style="height: 70vh; min-height: 400px;"
          data-graph={Jason.encode!(@graph_data)}
        >
          <canvas id="graph-canvas" style="width: 100%; height: 100%;"></canvas>
          <div id="graph-tooltip" class="graph-tooltip"></div>
          <%!-- Empty state --%>
          <div
            id="graph-empty"
            class="absolute inset-0 flex flex-col items-center justify-center"
            style="display: none;"
          >
            <.icon name="hero-share" class="size-12 opacity-20 mb-3" />
            <p class="text-sm opacity-40">No entities or relationships to display</p>
          </div>
          <%!-- Controls --%>
          <div class="absolute bottom-3 right-3 flex gap-1">
            <button
              id="graph-zoom-in"
              class="btn btn-xs btn-square bg-base-100/80 backdrop-blur-sm border-base-300/50 hover:bg-base-100"
            >
              <.icon name="hero-plus" class="size-3.5" />
            </button>
            <button
              id="graph-zoom-out"
              class="btn btn-xs btn-square bg-base-100/80 backdrop-blur-sm border-base-300/50 hover:bg-base-100"
            >
              <.icon name="hero-minus" class="size-3.5" />
            </button>
            <button
              id="graph-fit"
              class="btn btn-xs bg-base-100/80 backdrop-blur-sm border-base-300/50 hover:bg-base-100 gap-1"
            >
              <.icon name="hero-arrows-pointing-out" class="size-3.5" /> Fit
            </button>
            <button
              id="graph-reset"
              class="btn btn-xs bg-base-100/80 backdrop-blur-sm border-base-300/50 hover:bg-base-100 gap-1"
            >
              <.icon name="hero-arrow-path" class="size-3.5" /> Reset
            </button>
          </div>
          <%!-- Info overlay --%>
          <div
            class="absolute top-3 left-3 text-[10px] opacity-40 pointer-events-none"
            id="graph-perf"
          >
          </div>
        </div>

        <%!-- Stats --%>
        <div class="grid grid-cols-2 gap-3">
          <div class="card-glass p-4 flex items-center gap-3">
            <div class="stat-icon-gradient w-9 h-9 rounded-lg flex items-center justify-center">
              <.icon name="hero-circle-stack" class="size-4 text-white" />
            </div>
            <div>
              <div class="text-xl font-bold">{@node_count}</div>
              <div class="text-xs opacity-50">Nodes</div>
            </div>
          </div>
          <div class="card-glass p-4 flex items-center gap-3">
            <div class="stat-icon-gradient w-9 h-9 rounded-lg flex items-center justify-center">
              <.icon name="hero-link" class="size-4 text-white" />
            </div>
            <div>
              <div class="text-xl font-bold">{@edge_count}</div>
              <div class="text-xs opacity-50">Relationships</div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ForceGraph">
      export default {
        mounted() {
          this.canvas = this.el.querySelector('#graph-canvas')
          this.ctx = this.canvas.getContext('2d')
          this.tooltip = this.el.querySelector('#graph-tooltip')
          this.emptyEl = this.el.querySelector('#graph-empty')
          this.perfEl = this.el.querySelector('#graph-perf')
          this.nodes = []
          this.edges = []
          this.colors = {}
          this.nodeMap = new Map()
          this.hiddenTypes = new Set()
          this.searchQuery = ''
          this.highlighted = new Set()
          this.transform = { x: 0, y: 0, k: 1 }
          this.dragging = null
          this.hovered = null
          this.animating = false
          this.alpha = 1.0
          this.dpr = window.devicePixelRatio || 1

          // Defer init to next frame so container has layout dimensions
          requestAnimationFrame(() => {
            this.resizeCanvas()
            const data = JSON.parse(this.el.dataset.graph)
            this.initGraph(data)
          })
          window.addEventListener('resize', () => this.resizeCanvas())

          this.handleEvent("graph-data", (data) => this.initGraph(data))
          this.handleEvent("graph-search", ({query}) => this.applySearch(query))
          this.handleEvent("graph-filter", ({hidden_types}) => {
            this.hiddenTypes = new Set(hidden_types)
            this.render()
          })

          // Zoom controls
          this.el.querySelector('#graph-zoom-in').addEventListener('click', () => {
            this.zoomBy(1.4)
          })
          this.el.querySelector('#graph-zoom-out').addEventListener('click', () => {
            this.zoomBy(1 / 1.4)
          })
          this.el.querySelector('#graph-fit').addEventListener('click', () => this.fitToView())
          this.el.querySelector('#graph-reset').addEventListener('click', () => {
            this.transform = { x: 0, y: 0, k: 1 }
            this.alpha = 1.0
            this.initPositions()
            this.startSimulation()
          })

          // Mouse wheel zoom (toward cursor)
          this.canvas.addEventListener('wheel', (e) => {
            e.preventDefault()
            const factor = e.deltaY > 0 ? 0.9 : 1.1
            const rect = this.canvas.getBoundingClientRect()
            const mx = e.clientX - rect.left
            const my = e.clientY - rect.top
            this.zoomAt(factor, mx, my)
          }, { passive: false })

          // Pan & drag
          let panning = false, panStart = { x: 0, y: 0 }
          let dragStartPos = null

          this.canvas.addEventListener('mousedown', (e) => {
            const { x: wx, y: wy } = this.screenToWorld(e.clientX, e.clientY)
            const node = this.hitTest(wx, wy)
            if (node) {
              this.dragging = node
              dragStartPos = { x: wx, y: wy }
              e.stopPropagation()
            } else {
              panning = true
              panStart = { x: e.clientX - this.transform.x, y: e.clientY - this.transform.y }
            }
          })

          window.addEventListener('mousemove', (e) => {
            if (panning && !this.dragging) {
              this.transform.x = e.clientX - panStart.x
              this.transform.y = e.clientY - panStart.y
              this.render()
            }
            if (this.dragging) {
              const { x, y } = this.screenToWorld(e.clientX, e.clientY)
              this.dragging.x = x
              this.dragging.y = y
              this.dragging.fx = x
              this.dragging.fy = y
              this.render()
            }
            // Hover detection
            if (!this.dragging && !panning) {
              const { x: wx, y: wy } = this.screenToWorld(e.clientX, e.clientY)
              const node = this.hitTest(wx, wy)
              if (node !== this.hovered) {
                this.hovered = node
                this.canvas.style.cursor = node ? 'pointer' : 'grab'
                if (node) {
                  const rect = this.el.getBoundingClientRect()
                  this.tooltip.style.opacity = '1'
                  this.tooltip.innerHTML = `<div class="font-semibold">${this.esc(node.type)}</div><div class="opacity-70 text-[11px] mt-0.5">${this.esc(node.id)}</div><div class="text-[10px] opacity-40 mt-1">${node._degree} connection${node._degree !== 1 ? 's' : ''}</div>`
                  this.tooltip.style.left = (e.clientX - rect.left + 14) + 'px'
                  this.tooltip.style.top = (e.clientY - rect.top - 10) + 'px'
                } else {
                  this.tooltip.style.opacity = '0'
                }
                this.render()
              } else if (node) {
                const rect = this.el.getBoundingClientRect()
                this.tooltip.style.left = (e.clientX - rect.left + 14) + 'px'
                this.tooltip.style.top = (e.clientY - rect.top - 10) + 'px'
              }
            }
          })

          window.addEventListener('mouseup', () => {
            if (this.dragging) {
              if (dragStartPos) {
                const dx = (this.dragging.x - dragStartPos.x)
                const dy = (this.dragging.y - dragStartPos.y)
                if (Math.sqrt(dx*dx + dy*dy) < 3) {
                  this.pushEvent("node-click", { id: this.dragging.id })
                }
              }
              delete this.dragging.fx
              delete this.dragging.fy
              this.dragging = null
              dragStartPos = null
              this.alpha = 0.3
              if (!this.animating) this.startSimulation()
            }
            panning = false
          })

          // Double-click to navigate
          this.canvas.addEventListener('dblclick', (e) => {
            const { x, y } = this.screenToWorld(e.clientX, e.clientY)
            const node = this.hitTest(x, y)
            if (node) this.pushEvent("node-click", { id: node.id })
          })
        },

        resizeCanvas() {
          const rect = this.canvas.parentElement.getBoundingClientRect()
          const w = rect.width || 800
          const h = rect.height || 500
          this.canvas.width = w * this.dpr
          this.canvas.height = h * this.dpr
          this.canvas.style.width = w + 'px'
          this.canvas.style.height = h + 'px'
          this.ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0)
          this.w = w
          this.h = h
          this.render()
        },

        initGraph(data) {
          this.nodes = (data.nodes || []).map(n => ({...n, vx: 0, vy: 0, _degree: 0, _radius: 0}))
          this.edges = data.edges || []
          this.colors = data.colors || {}
          this.nodeMap = new Map(this.nodes.map(n => [n.id, n]))

          if (this.nodes.length === 0) {
            this.emptyEl.style.display = 'flex'
            this.ctx.clearRect(0, 0, this.w, this.h)
            return
          }
          this.emptyEl.style.display = 'none'

          // Pre-compute degree and radius
          this.nodes.forEach(n => { n._degree = 0 })
          this.edges.forEach(e => {
            const s = this.nodeMap.get(e.source)
            const t = this.nodeMap.get(e.target)
            if (s) s._degree++
            if (t) t._degree++
          })
          this.nodes.forEach(n => {
            n._radius = 12 + Math.min(n._degree * 3, 24)
          })

          // Pre-compute type centroids for clustering
          this.typeCentroids = {}
          const typeGroups = {}
          this.nodes.forEach(n => {
            if (!typeGroups[n.type]) typeGroups[n.type] = []
            typeGroups[n.type].push(n)
          })
          const typeNames = Object.keys(typeGroups)
          typeNames.forEach((type, i) => {
            const angle = (2 * Math.PI * i) / typeNames.length
            const r = Math.min(this.w, this.h) * 0.38
            this.typeCentroids[type] = {
              x: this.w / 2 + r * Math.cos(angle),
              y: this.h / 2 + r * Math.sin(angle)
            }
          })

          this.initPositions()
          this.startSimulation()
        },

        initPositions() {
          const cx = this.w / 2, cy = this.h / 2
          this.nodes.forEach((n, i) => {
            const tc = this.typeCentroids[n.type] || { x: cx, y: cy }
            const angle = (2 * Math.PI * i) / this.nodes.length
            n.x = tc.x + (Math.random() - 0.5) * 250
            n.y = tc.y + (Math.random() - 0.5) * 250
            n.vx = 0
            n.vy = 0
          })
        },

        applySearch(query) {
          this.searchQuery = query.toLowerCase()
          this.highlighted.clear()
          if (this.searchQuery) {
            this.nodes.forEach(n => {
              if (n.id.toLowerCase().includes(this.searchQuery) ||
                  n.label.toLowerCase().includes(this.searchQuery) ||
                  n.type.toLowerCase().includes(this.searchQuery)) {
                this.highlighted.add(n.id)
              }
            })
          }
          this.render()
        },

        // ======== QUADTREE for Barnes-Hut ========
        buildQuadtree(nodes) {
          if (nodes.length === 0) return null
          let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
          nodes.forEach(n => {
            if (n.x < minX) minX = n.x
            if (n.y < minY) minY = n.y
            if (n.x > maxX) maxX = n.x
            if (n.y > maxY) maxY = n.y
          })
          const pad = 10
          const root = { x: minX - pad, y: minY - pad, w: Math.max(maxX - minX + pad*2, 1), h: Math.max(maxY - minY + pad*2, 1), cx: 0, cy: 0, mass: 0, children: null, node: null }
          nodes.forEach(n => this.qtInsert(root, n))
          this.qtComputeMass(root)
          return root
        },
        qtInsert(quad, node) {
          if (quad.mass === 0 && !quad.node && !quad.children) {
            quad.node = node
            quad.mass = 1
            return
          }
          if (!quad.children) {
            quad.children = [null, null, null, null]
            if (quad.node) {
              const old = quad.node
              quad.node = null
              this.qtInsertChild(quad, old)
            }
          }
          this.qtInsertChild(quad, node)
          quad.mass++
        },
        qtInsertChild(quad, node) {
          const mx = quad.x + quad.w / 2
          const my = quad.y + quad.h / 2
          const hw = quad.w / 2, hh = quad.h / 2
          let qi
          if (node.x < mx) {
            qi = node.y < my ? 0 : 2
          } else {
            qi = node.y < my ? 1 : 3
          }
          if (!quad.children[qi]) {
            const qx = qi % 2 === 0 ? quad.x : mx
            const qy = qi < 2 ? quad.y : my
            quad.children[qi] = { x: qx, y: qy, w: hw, h: hh, cx: 0, cy: 0, mass: 0, children: null, node: null }
          }
          this.qtInsert(quad.children[qi], node)
        },
        qtComputeMass(quad) {
          if (!quad) return
          if (quad.node) {
            quad.cx = quad.node.x
            quad.cy = quad.node.y
            quad.mass = 1
            return
          }
          if (quad.children) {
            let totalMass = 0, cx = 0, cy = 0
            for (let i = 0; i < 4; i++) {
              const c = quad.children[i]
              if (c) {
                this.qtComputeMass(c)
                totalMass += c.mass
                cx += c.cx * c.mass
                cy += c.cy * c.mass
              }
            }
            quad.mass = totalMass
            quad.cx = totalMass > 0 ? cx / totalMass : quad.x + quad.w / 2
            quad.cy = totalMass > 0 ? cy / totalMass : quad.y + quad.h / 2
          }
        },
        qtForce(quad, node, theta, alpha) {
          if (!quad || quad.mass === 0) return
          const dx = quad.cx - node.x
          const dy = quad.cy - node.y
          const dist2 = dx * dx + dy * dy
          const dist = Math.sqrt(dist2) || 1

          // If leaf with same node, skip
          if (quad.node === node) return

          // If leaf or sufficiently far away, treat as single body
          if (quad.node || (quad.w / dist < theta)) {
            const charge = -2800 * alpha * quad.mass
            const f = charge / (dist2 + 1)
            node.vx += (dx / dist) * f
            node.vy += (dy / dist) * f
            return
          }

          // Otherwise recurse
          if (quad.children) {
            for (let i = 0; i < 4; i++) {
              this.qtForce(quad.children[i], node, theta, alpha)
            }
          }
        },

        startSimulation() {
          this.animating = true
          this.alpha = Math.max(this.alpha, 0.3)
          let lastTime = performance.now()
          const tick = (now) => {
            if (!this.animating) return
            const dt = Math.min((now - lastTime) / 16.67, 2)
            lastTime = now
            this.simulate(dt)
            this.render()
            this.alpha *= 0.992
            if (this.alpha > 0.001) {
              requestAnimationFrame(tick)
            } else {
              this.animating = false
              this.fitToView()
            }
          }
          requestAnimationFrame(tick)
        },

        simulate(dt) {
          const nodes = this.nodes
          const edges = this.edges
          const alpha = this.alpha
          const cx = this.w / 2, cy = this.h / 2

          // Barnes-Hut charge repulsion
          const visibleNodes = nodes.filter(n => !this.hiddenTypes.has(n.type))
          const qt = this.buildQuadtree(visibleNodes)
          const theta = 0.7
          visibleNodes.forEach(n => {
            if (n.fx !== undefined) return
            this.qtForce(qt, n, theta, alpha)
          })

          // Link attraction
          const linkDist = 180 + Math.max(0, (nodes.length - 30) * 1.6)
          const linkStr = 0.05 * alpha
          edges.forEach(e => {
            const s = this.nodeMap.get(e.source)
            const t = this.nodeMap.get(e.target)
            if (!s || !t) return
            if (this.hiddenTypes.has(s.type) || this.hiddenTypes.has(t.type)) return
            const dx = t.x - s.x, dy = t.y - s.y
            const dist = Math.sqrt(dx * dx + dy * dy) || 1
            const f = (dist - linkDist) * linkStr
            const fx = (dx / dist) * f, fy = (dy / dist) * f
            if (s.fx === undefined) { s.vx += fx; s.vy += fy }
            if (t.fx === undefined) { t.vx -= fx; t.vy -= fy }
          })

          // Type clustering force
          const clusterStr = 0.010 * alpha
          nodes.forEach(n => {
            if (n.fx !== undefined || this.hiddenTypes.has(n.type)) return
            const tc = this.typeCentroids[n.type]
            if (tc) {
              n.vx += (tc.x - n.x) * clusterStr
              n.vy += (tc.y - n.y) * clusterStr
            }
          })

          // Center gravity
          const centerStr = 0.012 * alpha
          nodes.forEach(n => {
            if (n.fx !== undefined || this.hiddenTypes.has(n.type)) return
            n.vx += (cx - n.x) * centerStr
            n.vy += (cy - n.y) * centerStr
          })

          // Velocity integration with damping
          const damping = 0.75
          nodes.forEach(n => {
            if (n.fx !== undefined) { n.x = n.fx; n.y = n.fy; return }
            if (this.hiddenTypes.has(n.type)) return
            n.vx *= damping
            n.vy *= damping
            n.x += n.vx * dt
            n.y += n.vy * dt
          })
        },

        render() {
          const ctx = this.ctx
          const w = this.w, h = this.h
          const { x: tx, y: ty, k } = this.transform
          const cx = w / 2, cy = h / 2

          ctx.clearRect(0, 0, w, h)
          ctx.save()
          ctx.translate(cx + tx, cy + ty)
          ctx.scale(k, k)
          ctx.translate(-cx, -cy)

          const showLabels = k > 0.3
          const showEdgeLabels = k > 0.55
          const hasSearch = this.highlighted.size > 0
          const dim = hasSearch ? 0.12 : 1

          // Pre-compute hovered node's neighbor sets for this frame
          const hoveredNeighborIds = new Set()
          const hoveredEdgeSet = new Set()
          if (this.hovered) {
            this.edges.forEach((e, ei) => {
              const isSource = e.source === this.hovered.id
              const isTarget = e.target === this.hovered.id
              if (isSource || isTarget) {
                hoveredEdgeSet.add(ei)
                hoveredNeighborIds.add(isSource ? e.target : e.source)
              }
            })
          }
          const hasHover = this.hovered !== null

          // Build a per-pair offset index for parallel edges (so they don't stack)
          const edgePairCount = new Map()
          const edgePairIndex = []
          this.edges.forEach(e => {
            const key = [e.source, e.target].sort().join('|')
            const idx = edgePairCount.get(key) || 0
            edgePairIndex.push(idx)
            edgePairCount.set(key, idx + 1)
          })

          // Draw edges
          this.edges.forEach((e, ei) => {
            const s = this.nodeMap.get(e.source)
            const t = this.nodeMap.get(e.target)
            if (!s || !t) return
            if (this.hiddenTypes.has(s.type) || this.hiddenTypes.has(t.type)) return

            const edgeHighlight = hasSearch && (this.highlighted.has(s.id) || this.highlighted.has(t.id))
            const isHoveredPath = hoveredEdgeSet.has(ei)
            const lineColor = isHoveredPath
              ? 'rgba(120, 160, 255, 0.85)'
              : edgeHighlight
                ? 'rgba(96, 130, 200, 0.7)'
                : (hasSearch || hasHover) ? 'rgba(150, 150, 150, 0.07)' : 'rgba(160, 160, 160, 0.28)'

            const dx = t.x - s.x, dy = t.y - s.y
            const dist = Math.sqrt(dx*dx + dy*dy) || 1

            // Quadratic bezier curve with lateral offset to separate parallel edges
            const pairIdx = edgePairIndex[ei]
            const curvature = 30 + pairIdx * 40
            const mx = (s.x + t.x) / 2 - (dy / dist) * curvature
            const my = (s.y + t.y) / 2 + (dx / dist) * curvature

            ctx.strokeStyle = lineColor
            ctx.lineWidth = isHoveredPath ? 2.5 : (edgeHighlight ? 2 : 1.5)
            ctx.beginPath()
            ctx.moveTo(s.x, s.y)
            ctx.quadraticCurveTo(mx, my, t.x, t.y)
            ctx.stroke()

            // Arrow at target node boundary (along the curve tangent)
            // Tangent at t = direction from control point to target
            const tdx = t.x - mx, tdy = t.y - my
            const tDist = Math.sqrt(tdx*tdx + tdy*tdy) || 1
            const nr = t._radius + 4
            const ax = t.x - (tdx/tDist) * nr
            const ay = t.y - (tdy/tDist) * nr
            const aSize = 8
            const angle = Math.atan2(tdy, tdx)
            const arrowColor = isHoveredPath ? 'rgba(120, 160, 255, 0.9)' : (edgeHighlight ? 'rgba(96, 130, 200, 0.75)' : 'rgba(160, 160, 160, 0.5)')
            ctx.fillStyle = arrowColor
            ctx.beginPath()
            ctx.moveTo(ax, ay)
            ctx.lineTo(ax - aSize * Math.cos(angle - 0.35), ay - aSize * Math.sin(angle - 0.35))
            ctx.lineTo(ax - aSize * Math.cos(angle + 0.35), ay - aSize * Math.sin(angle + 0.35))
            ctx.closePath()
            ctx.fill()

          })

          // ── Edge label pass (separate so labels always sit above lines) ──────
          // Only show labels for edges touching the hovered node or a highlighted
          // node. Use an AABB registry to skip any pill that would overlap one
          // already placed this frame.
          if (showEdgeLabels) {
            const isDark = document.documentElement.getAttribute('data-theme') !== 'light'
            const placedPills = [] // [{x, y, w, h}] in world coords

            const pillCollides = (px, py, pw, ph) => {
              const margin = 4
              return placedPills.some(p =>
                px - pw/2 - margin < p.x + p.w/2 &&
                px + pw/2 + margin > p.x - p.w/2 &&
                py - ph/2 - margin < p.y + p.h/2 &&
                py + ph/2 + margin > p.y - p.h/2
              )
            }

            ctx.font = 'bold 10px system-ui'
            ctx.textAlign = 'center'

            // Sort so hovered/highlighted edges are placed first (highest priority)
            const sortedEdgeIndices = this.edges
              .map((e, i) => i)
              .sort((ai, bi) => {
                const aHov = hoveredEdgeSet.has(ai)
                const bHov = hoveredEdgeSet.has(bi)
                const ea = this.edges[ai], eb = this.edges[bi]
                const aHl = hasSearch && (this.highlighted.has(ea.source) || this.highlighted.has(ea.target))
                const bHl = hasSearch && (this.highlighted.has(eb.source) || this.highlighted.has(eb.target))
                return ((bHov ? 2 : 0) + (bHl ? 1 : 0)) - ((aHov ? 2 : 0) + (aHl ? 1 : 0))
              })

            sortedEdgeIndices.forEach(ei => {
              const e = this.edges[ei]
              if (!e.label) return
              const s = this.nodeMap.get(e.source)
              const t = this.nodeMap.get(e.target)
              if (!s || !t) return
              if (this.hiddenTypes.has(s.type) || this.hiddenTypes.has(t.type)) return

              const edgeHighlight = hasSearch && (this.highlighted.has(s.id) || this.highlighted.has(t.id))
              const isHoveredEdge = hoveredEdgeSet.has(ei)

              const dx = t.x - s.x, dy = t.y - s.y
              const dist = Math.sqrt(dx*dx + dy*dy) || 1
              const pairIdx = edgePairIndex[ei]
              const curvature = 30 + pairIdx * 40
              const lx = (s.x + t.x) / 2 - (dy / dist) * curvature
              const ly = (s.y + t.y) / 2 + (dx / dist) * curvature

              const textW = ctx.measureText(e.label).width
              const padX = 6
              const pillW = textW + padX * 2
              const pillH = 16

              if (pillCollides(lx, ly, pillW, pillH)) return
              placedPills.push({ x: lx, y: ly, w: pillW, h: pillH })

              const labelAlpha = isHoveredEdge ? 1 : (edgeHighlight ? 0.95 : (hasSearch || hasHover ? dim * 0.4 : 0.75))

              // Background pill
              ctx.globalAlpha = labelAlpha
              ctx.fillStyle = isDark ? 'rgba(22, 24, 40, 0.92)' : 'rgba(248, 249, 253, 0.94)'
              ctx.beginPath()
              ctx.roundRect(lx - pillW/2, ly - pillH/2, pillW, pillH, 5)
              ctx.fill()
              // Border
              ctx.strokeStyle = isHoveredEdge
                ? 'rgba(96, 130, 200, 0.7)'
                : (edgeHighlight ? 'rgba(96, 130, 200, 0.5)' : (isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.1)'))
              ctx.lineWidth = isHoveredEdge ? 1 : 0.75
              ctx.stroke()
              // Text
              ctx.fillStyle = isHoveredEdge || edgeHighlight
                ? (isDark ? 'rgba(150, 180, 255, 1)' : 'rgba(50, 80, 200, 1)')
                : (isDark ? 'rgba(200, 210, 230, 1)' : 'rgba(55, 60, 85, 1)')
              ctx.fillText(e.label, lx, ly + 4)
              ctx.globalAlpha = 1
            })
          }

          // Draw nodes
          this.nodes.forEach(n => {
            if (this.hiddenTypes.has(n.type)) return
            const color = this.colors[n.type] || '#6b7280'
            const r = n._radius
            const isHighlighted = hasSearch && this.highlighted.has(n.id)
            const isHovered = this.hovered === n
            const isNeighbor = hasHover && hoveredNeighborIds.has(n.id)
            // Dim everything that isn't part of the hovered path or a search result
            const nodeAlpha = isHovered || isNeighbor
              ? 1
              : (isHighlighted ? 1 : (hasSearch ? dim : (hasHover ? 0.15 : 1)))

            // Glow for highlighted/hovered/neighbor
            if (isHighlighted || isHovered || isNeighbor) {
              ctx.shadowColor = isNeighbor && !isHovered ? 'rgba(120, 160, 255, 0.6)' : color
              ctx.shadowBlur = isHovered ? 24 : (isNeighbor ? 14 : 12)
            }

            // Node circle
            ctx.globalAlpha = nodeAlpha * 0.85
            ctx.fillStyle = color
            ctx.beginPath()
            ctx.arc(n.x, n.y, isHovered ? r * 1.15 : r, 0, Math.PI * 2)
            ctx.fill()

            // Stroke
            ctx.globalAlpha = nodeAlpha * 0.25
            ctx.strokeStyle = color
            ctx.lineWidth = 3
            ctx.stroke()

            ctx.shadowColor = 'transparent'
            ctx.shadowBlur = 0
            ctx.globalAlpha = 1

            // Neighbor ring — blue pulse ring around direct neighbors
            if (isNeighbor) {
              ctx.strokeStyle = 'rgba(120, 160, 255, 0.7)'
              ctx.lineWidth = 2
              ctx.globalAlpha = 0.85
              ctx.beginPath()
              ctx.arc(n.x, n.y, r + 5, 0, Math.PI * 2)
              ctx.stroke()
              ctx.globalAlpha = 1
            }

            // Search ring
            if (isHighlighted) {
              ctx.strokeStyle = '#fbbf24'
              ctx.lineWidth = 2
              ctx.globalAlpha = 0.9
              ctx.beginPath()
              ctx.arc(n.x, n.y, r + 4, 0, Math.PI * 2)
              ctx.stroke()
              ctx.globalAlpha = 1
            }

            // Labels (level of detail)
            if (showLabels || isHovered || isHighlighted) {
              const isDark = document.documentElement.getAttribute('data-theme') !== 'light'
              const labelAlpha = isHovered || isNeighbor ? 1 : (isHighlighted ? 1 : (hasSearch || hasHover ? dim * 0.6 : 1))
              const fontSize = Math.max(10, Math.min(Math.round(r * 0.72), 15))
              ctx.font = `${isHovered || isHighlighted ? 'bold ' : 'bold '}${fontSize}px system-ui`
              ctx.textAlign = 'center'
              ctx.globalAlpha = labelAlpha
              if (r >= 16) {
                // Label inside node — white/dark text centered
                ctx.fillStyle = isDark ? 'rgba(255,255,255,0.92)' : 'rgba(20,20,40,0.9)'
                ctx.fillText(n.label, n.x, n.y + fontSize * 0.35)
              } else {
                // Label below small node with subtle shadow
                ctx.shadowColor = isDark ? 'rgba(0,0,0,0.7)' : 'rgba(255,255,255,0.9)'
                ctx.shadowBlur = 4
                ctx.fillStyle = isDark ? 'rgba(210,210,230,0.95)' : 'rgba(30,30,60,0.9)'
                ctx.fillText(n.label, n.x, n.y + r + 13)
                ctx.shadowBlur = 0
                ctx.shadowColor = 'transparent'
              }
              ctx.globalAlpha = 1
            }
          })

          ctx.restore()
        },

        // Convert screen coordinates to world coordinates
        screenToWorld(clientX, clientY) {
          const rect = this.canvas.getBoundingClientRect()
          const sx = clientX - rect.left
          const sy = clientY - rect.top
          const { x: tx, y: ty, k } = this.transform
          const cx = this.w / 2, cy = this.h / 2
          return {
            x: (sx - cx - tx) / k + cx,
            y: (sy - cy - ty) / k + cy
          }
        },

        hitTest(wx, wy) {
          for (let i = this.nodes.length - 1; i >= 0; i--) {
            const n = this.nodes[i]
            if (this.hiddenTypes.has(n.type)) continue
            const dx = n.x - wx, dy = n.y - wy
            if (dx * dx + dy * dy < (n._radius + 4) * (n._radius + 4)) return n
          }
          return null
        },

        zoomBy(factor) {
          this.transform.k = Math.max(0.1, Math.min(8, this.transform.k * factor))
          this.render()
        },

        zoomAt(factor, sx, sy) {
          const cx = this.w / 2, cy = this.h / 2
          const oldK = this.transform.k
          const newK = Math.max(0.1, Math.min(8, oldK * factor))
          // Zoom toward cursor
          this.transform.x = sx - cx - (sx - cx - this.transform.x) * (newK / oldK)
          this.transform.y = sy - cy - (sy - cy - this.transform.y) * (newK / oldK)
          this.transform.k = newK
          this.render()
        },

        fitToView() {
          const visible = this.nodes.filter(n => !this.hiddenTypes.has(n.type))
          if (visible.length === 0) return
          let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
          visible.forEach(n => {
            const r = n._radius + 20
            if (n.x - r < minX) minX = n.x - r
            if (n.y - r < minY) minY = n.y - r
            if (n.x + r > maxX) maxX = n.x + r
            if (n.y + r > maxY) maxY = n.y + r
          })
          const gw = maxX - minX || 1, gh = maxY - minY || 1
          const pad = 40
          const kx = (this.w - pad * 2) / gw
          const ky = (this.h - pad * 2) / gh
          const k = Math.min(kx, ky, 3)
          const gcx = (minX + maxX) / 2, gcy = (minY + maxY) / 2
          this.transform.k = k
          this.transform.x = (this.w / 2 - gcx) * k + (this.w / 2) * (1 - k)
          this.transform.y = (this.h / 2 - gcy) * k + (this.h / 2) * (1 - k)
          this.render()
        },

        esc(str) {
          return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
        }
      }
    </script>
    """
  end
end
