defmodule PhaetonWeb.ClusterLive do
  use PhaetonWeb, :live_view

  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Cluster")
      |> assign(:selected_node, nil)
      |> assign_cluster_snapshot()

    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_ms)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, assign_cluster_snapshot(socket)}
  end

  @impl true
  def handle_event("select_node", %{"node" => node_name}, socket) do
    {:noreply, assign(socket, :selected_node, node_name)}
  end

  @impl true
  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:cluster} current_scope={@current_scope}>
      <%= if @selected_node do %>
        <% node_info = Enum.find(@cluster.nodes, fn n -> n.name == @selected_node end) %>
        <% is_local = @selected_node == @cluster.local_node %>
        <div class="space-y-6">
          <div class="flex items-center gap-3">
            <button phx-click="back" class="btn btn-sm btn-ghost gap-1.5">
              <.icon name="hero-arrow-left" class="size-4" /> All Nodes
            </button>
            <div>
              <h1 class="text-2xl font-bold tracking-tight heading-gradient">{@selected_node}</h1>
              <p class="text-sm opacity-60 mt-1">
                {if is_local, do: "Local node", else: "Remote node"}
              </p>
            </div>
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div class="stat-card card bg-base-200 p-4">
              <div class="flex items-center gap-3">
                <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                  <.icon name="hero-signal" class="size-5 text-white" />
                </div>
                <div>
                  <div class="text-xl font-bold">
                    {if node_info && node_info.connected, do: "Online", else: "Offline"}
                  </div>
                  <div class="text-xs opacity-60 font-semibold">Status</div>
                </div>
              </div>
            </div>

            <div class="stat-card card bg-base-200 p-4">
              <div class="flex items-center gap-3">
                <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                  <.icon name="hero-cube" class="size-5 text-white" />
                </div>
                <div>
                  <div class="text-2xl font-bold">{(node_info && node_info.entity_count) || 0}</div>
                  <div class="text-xs opacity-60 font-semibold">Entity Servers</div>
                </div>
              </div>
            </div>

            <%= if is_local do %>
              <div class="stat-card card bg-base-200 p-4">
                <div class="flex items-center gap-3">
                  <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                    <.icon name="hero-cpu-chip" class="size-5 text-white" />
                  </div>
                  <div>
                    <div class="text-2xl font-bold">{@cluster.schedulers_online}</div>
                    <div class="text-xs opacity-60 font-semibold">Schedulers</div>
                  </div>
                </div>
              </div>

              <div class="stat-card card bg-base-200 p-4">
                <div class="flex items-center gap-3">
                  <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                    <.icon name="hero-bolt" class="size-5 text-white" />
                  </div>
                  <div>
                    <div class="text-2xl font-bold">{@cluster.total_memory_mb} MB</div>
                    <div class="text-xs opacity-60 font-semibold">BEAM Memory</div>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="stat-card card bg-base-200 p-4">
                <div class="flex items-center gap-3">
                  <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                    <.icon name="hero-eye" class="size-5 text-white" />
                  </div>
                  <div>
                    <div class="text-xl font-bold capitalize">
                      {(node_info && node_info.visibility) || "—"}
                    </div>
                    <div class="text-xs opacity-60 font-semibold">Visibility</div>
                  </div>
                </div>
              </div>

              <div class="stat-card card bg-base-200 p-4">
                <div class="flex items-center gap-3">
                  <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                    <.icon name="hero-globe-alt" class="size-5 text-white" />
                  </div>
                  <div>
                    <div class="text-xl font-bold">Remote</div>
                    <div class="text-xs opacity-60 font-semibold">Role</div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
            <div class="card-glass p-5">
              <h2 class="font-bold text-sm mb-4 flex items-center gap-2">
                <.icon name="hero-information-circle" class="size-4" /> Node Information
              </h2>
              <div class="space-y-0 text-sm divide-y divide-base-content/10">
                <div class="flex justify-between items-center py-2">
                  <span class="opacity-60">Full name</span>
                  <span class="font-mono text-xs">{@selected_node}</span>
                </div>
                <div class="flex justify-between items-center py-2">
                  <span class="opacity-60">Role</span>
                  <span class="font-semibold">{if is_local, do: "Local", else: "Remote"}</span>
                </div>
                <div class="flex justify-between items-center py-2">
                  <span class="opacity-60">Status</span>
                  <span class={[
                    "badge badge-sm",
                    node_info && node_info.connected && "badge-success",
                    (!node_info || !node_info.connected) && "badge-ghost"
                  ]}>
                    {if node_info && node_info.connected, do: "Connected", else: "Disconnected"}
                  </span>
                </div>
                <%= if not is_local do %>
                  <div class="flex justify-between items-center py-2">
                    <span class="opacity-60">Visibility</span>
                    <span class="badge badge-sm badge-outline capitalize">
                      {(node_info && node_info.visibility) || "Unknown"}
                    </span>
                  </div>
                <% end %>
                <div class="flex justify-between items-center py-2">
                  <span class="opacity-60">Entity Servers</span>
                  <span class="font-semibold">{(node_info && node_info.entity_count) || 0}</span>
                </div>
              </div>
            </div>

            <%= if is_local do %>
              <div class="card-glass p-5">
                <h2 class="font-bold text-sm mb-4 flex items-center gap-2">
                  <.icon name="hero-cpu-chip" class="size-4" /> Runtime
                </h2>
                <div class="space-y-0 text-sm divide-y divide-base-content/10">
                  <div class="flex justify-between items-center py-2">
                    <span class="opacity-60">Processes</span>
                    <span class="font-semibold">{@cluster.process_count}</span>
                  </div>
                  <div class="flex justify-between items-center py-2">
                    <span class="opacity-60">Ports</span>
                    <span class="font-semibold">{@cluster.port_count}</span>
                  </div>
                  <div class="flex justify-between items-center py-2">
                    <span class="opacity-60">Schedulers</span>
                    <span class="font-semibold">{@cluster.schedulers_online}</span>
                  </div>
                  <div class="flex justify-between items-center py-2">
                    <span class="opacity-60">Total Memory</span>
                    <span class="font-semibold">{@cluster.total_memory_mb} MB</span>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="space-y-6">
          <div>
            <h1 class="text-2xl font-bold tracking-tight heading-gradient">Distributed Operations</h1>
            <p class="text-sm opacity-60 mt-1">Node topology, connectivity, and runtime health</p>
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div class="stat-card card bg-base-200 p-4">
              <div class="flex items-center gap-3">
                <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                  <.icon name="hero-server" class="size-5 text-white" />
                </div>
                <div>
                  <div class="text-2xl font-bold">{@cluster.node_count}</div>
                  <div class="text-xs opacity-60 font-semibold">Known Nodes</div>
                </div>
              </div>
            </div>

            <div class="stat-card card bg-base-200 p-4">
              <div class="flex items-center gap-3">
                <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                  <.icon name="hero-link" class="size-5 text-white" />
                </div>
                <div>
                  <div class="text-2xl font-bold">{@cluster.connected_count}</div>
                  <div class="text-xs opacity-60 font-semibold">Connected Nodes</div>
                </div>
              </div>
            </div>

            <div class="stat-card card bg-base-200 p-4">
              <div class="flex items-center gap-3">
                <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                  <.icon name="hero-cpu-chip" class="size-5 text-white" />
                </div>
                <div>
                  <div class="text-2xl font-bold">{@cluster.schedulers_online}</div>
                  <div class="text-xs opacity-60 font-semibold">Schedulers</div>
                </div>
              </div>
            </div>

            <div class="stat-card card bg-base-200 p-4">
              <div class="flex items-center gap-3">
                <div class="stat-icon-gradient w-10 h-10 rounded-[5px] flex items-center justify-center">
                  <.icon name="hero-bolt" class="size-5 text-white" />
                </div>
                <div>
                  <div class="text-2xl font-bold">{@cluster.total_memory_mb} MB</div>
                  <div class="text-xs opacity-60 font-semibold">BEAM Memory</div>
                </div>
              </div>
            </div>
          </div>

          <%= if not @cluster.distributed? do %>
            <div class="card-glass p-4">
              <div class="flex items-start gap-3">
                <.icon name="hero-exclamation-triangle" class="size-5 text-warning shrink-0 mt-0.5" />
                <div class="text-sm">
                  <div class="font-bold">Node is running in standalone mode</div>
                  <p class="opacity-70 mt-1">
                    Start with a node name (e.g. mix phx.server --sname phaeton) to enable distributed connectivity.
                  </p>
                </div>
              </div>
            </div>
          <% end %>

          <div class="grid grid-cols-1 xl:grid-cols-3 gap-4">
            <div class="card-glass p-5 xl:col-span-2">
              <h2 class="font-bold text-sm mb-1 flex items-center gap-2">
                <.icon name="hero-share" class="size-4" /> Node Topology
              </h2>
              <p class="text-xs opacity-50 mb-3">Click a node to view its details</p>

              <div class="rounded-[5px] border-2 border-nb bg-base-100/50 min-h-[320px] p-3">
                <svg viewBox="0 0 100 100" class="w-full h-[300px]">
                  <line
                    :for={edge <- @cluster.topology.edges}
                    x1={edge.from_x}
                    y1={edge.from_y}
                    x2={edge.to_x}
                    y2={edge.to_y}
                    class="stroke-base-content/30"
                    stroke-width="0.8"
                  />

                  <g :for={point <- @cluster.topology.points}>
                    <circle
                      cx={point.x}
                      cy={point.y}
                      r="8"
                      class="fill-transparent cursor-pointer hover:fill-base-content/10 transition-all"
                      phx-click="select_node"
                      phx-value-node={point.name}
                    />
                    <circle
                      cx={point.x}
                      cy={point.y}
                      r="5.2"
                      class={[
                        "stroke-2 pointer-events-none",
                        point.self && "fill-primary stroke-nb",
                        !point.self && point.connected && "fill-secondary stroke-nb",
                        !point.self && !point.connected && "fill-base-300 stroke-nb"
                      ]}
                    />
                    <text
                      x={point.x}
                      y={point.y + 11}
                      text-anchor="middle"
                      class="fill-base-content text-[3px] font-semibold pointer-events-none"
                    >
                      {point.label}
                    </text>
                  </g>
                </svg>
              </div>
            </div>

            <div class="card-glass p-5">
              <h2 class="font-bold text-sm mb-3 flex items-center gap-2">
                <.icon name="hero-signal" class="size-4" /> Runtime Status
              </h2>

              <div class="space-y-0 text-sm divide-y divide-base-content/10">
                <div class="flex items-center justify-between py-2">
                  <span class="opacity-60">Local node</span>
                  <span class="font-mono text-xs">{@cluster.local_node}</span>
                </div>
                <div class="flex items-center justify-between py-2">
                  <span class="opacity-60">Mode</span>
                  <span class="badge badge-sm">
                    {if @cluster.distributed?, do: "Distributed", else: "Standalone"}
                  </span>
                </div>
                <div class="flex items-center justify-between py-2">
                  <span class="opacity-60">Processes</span>
                  <span class="font-semibold">{@cluster.process_count}</span>
                </div>
                <div class="flex items-center justify-between py-2">
                  <span class="opacity-60">Ports</span>
                  <span class="font-semibold">{@cluster.port_count}</span>
                </div>
                <div class="flex items-center justify-between py-2">
                  <span class="opacity-60">Visible nodes</span>
                  <span class="font-semibold">{@cluster.visible_count}</span>
                </div>
                <div class="flex items-center justify-between py-2">
                  <span class="opacity-60">Hidden nodes</span>
                  <span class="font-semibold">{@cluster.hidden_count}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="card-glass p-5">
            <h2 class="font-bold text-sm mb-3 flex items-center gap-2">
              <.icon name="hero-server-stack" class="size-4" /> Nodes
            </h2>
            <p class="text-xs opacity-50 mb-3">Click a row to view node details</p>

            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-xs font-bold">
                    <th>Node</th>
                    <th>Status</th>
                    <th>Visibility</th>
                    <th>Role</th>
                    <th>Entity Servers</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={n <- @cluster.nodes}
                    class="hover:bg-base-300/40 transition-colors cursor-pointer"
                    phx-click="select_node"
                    phx-value-node={n.name}
                  >
                    <td class="font-mono text-xs">{n.name}</td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        n.connected && "badge-success",
                        !n.connected && "badge-ghost"
                      ]}>
                        {if n.connected, do: "Connected", else: "Unknown"}
                      </span>
                    </td>
                    <td>
                      <span class="badge badge-sm badge-outline">{n.visibility}</span>
                    </td>
                    <td>
                      <span class="text-xs font-semibold">
                        {if n.self, do: "Local", else: "Remote"}
                      </span>
                    </td>
                    <td>
                      <span class="text-xs font-semibold">{n.entity_count}</span>
                    </td>
                  </tr>
                  <tr :if={@cluster.nodes == []}>
                    <td colspan="5" class="text-center py-8 opacity-50">No nodes discovered</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp assign_cluster_snapshot(socket) do
    assign(socket, :cluster, cluster_snapshot())
  end

  defp cluster_snapshot do
    local = node()
    connected = Node.list(:connected)
    visible = Node.list(:visible)
    hidden = Node.list(:hidden)

    known_nodes =
      [local | connected ++ visible ++ hidden]
      |> Enum.uniq()
      |> Enum.sort()

    nodes =
      Enum.map(known_nodes, fn n ->
        visibility =
          cond do
            n in hidden -> "hidden"
            n in visible -> "visible"
            true -> "connected"
          end

        %{
          name: Atom.to_string(n),
          connected: n == local or n in connected,
          visibility: visibility,
          self: n == local,
          entity_count: fetch_entity_count(n)
        }
      end)

    %{
      local_node: Atom.to_string(local),
      distributed?: local != :nonode@nohost,
      node_count: length(known_nodes),
      connected_count: length(connected),
      visible_count: length(visible),
      hidden_count: length(hidden),
      schedulers_online: :erlang.system_info(:schedulers_online),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      total_memory_mb: memory_mb(:total),
      nodes: nodes,
      topology: topology(known_nodes, local, connected)
    }
  end

  defp fetch_entity_count(target_node) do
    :global.registered_names()
    |> Enum.filter(&match?({Phaeton.NGSI.EntityRegistry, _}, &1))
    |> Enum.count(fn name ->
      pid = :global.whereis_name(name)
      pid != :undefined and node(pid) == target_node
    end)
  end

  defp topology(nodes, local, connected) do
    count = length(nodes)

    points =
      if count <= 1 do
        [
          %{
            node: local,
            x: 50,
            y: 50,
            label: short_node(local),
            name: Atom.to_string(local),
            connected: true,
            self: true
          }
        ]
      else
        Enum.with_index(nodes)
        |> Enum.map(fn {n, idx} ->
          angle = 2 * :math.pi() * idx / count
          x = 50 + 35 * :math.cos(angle)
          y = 50 + 35 * :math.sin(angle)

          %{
            node: n,
            x: x,
            y: y,
            label: short_node(n),
            name: Atom.to_string(n),
            connected: n == local or n in connected,
            self: n == local
          }
        end)
      end

    points_by_node = Map.new(points, &{&1.node, &1})

    edges =
      Enum.flat_map(connected, fn n ->
        case {Map.get(points_by_node, local), Map.get(points_by_node, n)} do
          {nil, _} ->
            []

          {_, nil} ->
            []

          {from, to} ->
            [%{from_x: from.x, from_y: from.y, to_x: to.x, to_y: to.y}]
        end
      end)

    %{points: points, edges: edges}
  end

  defp short_node(n) do
    n
    |> Atom.to_string()
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 14)
  end

  defp memory_mb(kind) do
    kind
    |> :erlang.memory()
    |> Kernel./(1_048_576)
    |> Float.round(1)
  end
end
