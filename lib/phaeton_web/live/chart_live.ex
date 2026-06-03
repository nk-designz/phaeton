defmodule PhaetonWeb.ChartLive do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI.Temporal
  alias Phaeton.Store

  @impl true
  def mount(params, _session, socket) do
    # Get list of entities with temporal data, filtered to the active tenant
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    t = tenant || :all
    {:ok, temporal_entities} = Temporal.query_temporal(%{"limit" => "10000"})

    allowed_ids = Store.list_distinct_subjects_by_tenant(t) |> MapSet.new()

    entity_options =
      temporal_entities
      |> Enum.filter(fn e -> t == :all or MapSet.member?(allowed_ids, e["id"]) end)
      |> Enum.map(fn e -> %{id: e["id"], type: e["type"]} end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id)

    # Pre-select entity from params
    selected_entity_id = Map.get(params, "entity")
    selected_attr = Map.get(params, "attr")

    {attrs, chart_data} =
      if selected_entity_id do
        load_entity_temporal(selected_entity_id, selected_attr)
      else
        {[], nil}
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phaeton.PubSub, "ngsi:entity_changes")
    end

    socket =
      socket
      |> assign(:page_title, "Charts")
      |> assign(:entity_options, entity_options)
      |> assign(:selected_entity_id, selected_entity_id)
      |> assign(:selected_attr, selected_attr)
      |> assign(:available_attrs, attrs)
      |> assign(:chart_data, chart_data)
      |> assign(:timerel, "between")
      |> assign(:time_at, default_time_at())
      |> assign(:end_time_at, default_end_time_at())

    {:ok, socket}
  end

  @impl true
  def handle_event("select-entity", %{"entity_id" => entity_id}, socket) do
    entity_id = if entity_id == "", do: nil, else: entity_id

    {attrs, _chart_data} =
      if entity_id do
        load_entity_temporal(entity_id, nil)
      else
        {[], nil}
      end

    {:noreply,
     socket
     |> assign(:selected_entity_id, entity_id)
     |> assign(:selected_attr, nil)
     |> assign(:available_attrs, attrs)
     |> assign(:chart_data, nil)}
  end

  def handle_event("select-attr", %{"attr" => attr}, socket) do
    attr = if attr == "", do: nil, else: attr
    entity_id = socket.assigns.selected_entity_id

    {_attrs, chart_data} =
      if entity_id && attr do
        load_entity_temporal(entity_id, attr)
      else
        {[], nil}
      end

    {:noreply,
     socket
     |> assign(:selected_attr, attr)
     |> assign(:chart_data, chart_data)}
  end

  def handle_event("apply-time-filter", params, socket) do
    timerel = params["timerel"] || "between"
    time_at = params["time_at"] || ""
    end_time_at = params["end_time_at"] || ""

    entity_id = socket.assigns.selected_entity_id
    attr = socket.assigns.selected_attr

    {attrs, chart_data} =
      if entity_id do
        load_entity_temporal_filtered(entity_id, attr, timerel, time_at, end_time_at)
      else
        {[], nil}
      end

    {:noreply,
     socket
     |> assign(:timerel, timerel)
     |> assign(:time_at, time_at)
     |> assign(:end_time_at, end_time_at)
     |> assign(:available_attrs, attrs)
     |> assign(:chart_data, chart_data)}
  end

  defp load_entity_temporal(entity_id, selected_attr) do
    case Temporal.retrieve_temporal(entity_id) do
      {:ok, temporal} ->
        attrs = extract_numeric_attrs(temporal)
        chart_data = if selected_attr, do: build_chart_data(temporal, selected_attr), else: nil
        {attrs, chart_data}

      {:error, _} ->
        {[], nil}
    end
  end

  defp load_entity_temporal_filtered(entity_id, selected_attr, timerel, time_at, end_time_at) do
    params =
      %{}
      |> maybe_put("timerel", timerel)
      |> maybe_put("timeAt", time_at)
      |> maybe_put("endTimeAt", end_time_at)

    case Temporal.retrieve_temporal(entity_id, params) do
      {:ok, temporal} ->
        attrs = extract_numeric_attrs(temporal)
        chart_data = if selected_attr, do: build_chart_data(temporal, selected_attr), else: nil
        {attrs, chart_data}

      {:error, _} ->
        {[], nil}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp extract_numeric_attrs(temporal) do
    temporal
    |> Map.drop(["id", "type", "@context"])
    |> Enum.filter(fn {_name, instances} ->
      is_list(instances) and
        Enum.any?(instances, fn inst ->
          inst["observedAt"] != nil and inst["value"] != nil
        end)
    end)
    |> Enum.map(fn {name, instances} ->
      timed = Enum.filter(instances, fn i -> i["observedAt"] != nil end)

      numeric? =
        Enum.any?(timed, fn i -> is_number(i["value"]) or parseable_number?(i["value"]) end)

      %{name: name, count: length(timed), kind: if(numeric?, do: "numeric", else: "state")}
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp parseable_number?(val) when is_binary(val) do
    case Float.parse(val) do
      {_, _} ->
        true

      :error ->
        case Integer.parse(val) do
          {_, _} -> true
          :error -> false
        end
    end
  end

  defp parseable_number?(_), do: false

  defp build_chart_data(temporal, attr_name) do
    case Map.get(temporal, attr_name) do
      nil ->
        nil

      instances when is_list(instances) ->
        timed =
          instances
          |> Enum.filter(fn inst -> inst["observedAt"] != nil end)
          |> Enum.sort_by(fn inst -> inst["observedAt"] end)

        if timed == [] do
          nil
        else
          numeric? =
            Enum.any?(timed, fn i -> is_number(i["value"]) or parseable_number?(i["value"]) end)

          if numeric? do
            build_numeric_chart(attr_name, timed)
          else
            build_state_chart(attr_name, timed)
          end
        end

      _ ->
        nil
    end
  end

  defp build_numeric_chart(attr_name, timed) do
    points =
      timed
      |> Enum.map(fn inst -> %{x: inst["observedAt"], y: parse_numeric(inst["value"])} end)
      |> Enum.filter(fn p -> p.y != nil end)

    if points == [] do
      nil
    else
      %{
        chart_type: "numeric",
        attr: attr_name,
        points: points,
        min: points |> Enum.map(& &1.y) |> Enum.min(),
        max: points |> Enum.map(& &1.y) |> Enum.max(),
        count: length(points)
      }
    end
  end

  defp build_state_chart(attr_name, timed) do
    segments =
      timed
      |> Enum.map(fn inst -> %{x: inst["observedAt"], value: stringify_state_value(inst["value"])} end)

    unique_values = segments |> Enum.map(& &1.value) |> Enum.uniq()

    %{
      chart_type: "state",
      attr: attr_name,
      segments: segments,
      unique_values: unique_values,
      count: length(segments)
    }
  end

  defp stringify_state_value(val) when is_binary(val), do: val
  defp stringify_state_value(val) when is_number(val), do: to_string(val)
  defp stringify_state_value(true), do: "true"
  defp stringify_state_value(false), do: "false"
  defp stringify_state_value(nil), do: "null"

  defp stringify_state_value(val) when is_map(val) or is_list(val) do
    Jason.encode!(val)
  end

  defp stringify_state_value(val), do: inspect(val)

  defp parse_numeric(val) when is_number(val), do: val

  defp parse_numeric(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} ->
        f

      :error ->
        case Integer.parse(val) do
          {i, _} -> i
          :error -> nil
        end
    end
  end

  defp parse_numeric(_), do: nil

  defp short_id(id), do: id |> String.split(":") |> List.last()

  defp default_time_at do
    DateTime.utc_now()
    |> DateTime.add(-7, :day)
    |> DateTime.to_iso8601()
    |> String.slice(0, 16)
  end

  defp default_end_time_at do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
    |> String.slice(0, 16)
  end

  @impl true
  def handle_info({:entity_changed, entity_id, _entity_data, _change_type}, socket) do
    selected = socket.assigns.selected_entity_id
    attr = socket.assigns.selected_attr

    # Refresh entity options list (new entities may have appeared), filtered to active tenant
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    t = tenant || :all
    {:ok, temporal_entities} = Temporal.query_temporal(%{"limit" => "10000"})
    allowed_ids = Store.list_distinct_subjects_by_tenant(t) |> MapSet.new()

    entity_options =
      temporal_entities
      |> Enum.filter(fn e -> t == :all or MapSet.member?(allowed_ids, e["id"]) end)
      |> Enum.map(fn e -> %{id: e["id"], type: e["type"]} end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id)

    socket = assign(socket, :entity_options, entity_options)

    # If the changed entity is currently selected, refresh chart
    socket =
      if entity_id == selected and attr do
        {attrs, chart_data} = load_entity_temporal(selected, attr)

        socket
        |> assign(:available_attrs, attrs)
        |> assign(:chart_data, chart_data)
        |> maybe_push_chart(chart_data)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:entity_deleted, _entity_id}, socket), do: {:noreply, socket}

  defp maybe_push_chart(socket, nil), do: socket

  defp maybe_push_chart(socket, chart_data) do
    push_event(socket, "update-chart", %{chart: chart_data})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:charts} current_scope={@current_scope}>
      <div class="space-y-4">
        <%!-- Header --%>
        <div>
          <h1 class="text-lg font-bold flex items-center gap-2 heading-gradient">
            <.icon name="hero-chart-bar" class="size-5 text-primary" /> Temporal Charts
          </h1>
          <p class="text-xs opacity-50 mt-0.5">
            Visualize attribute values over time
          </p>
        </div>

        <%!-- Controls --%>
        <div class="card-glass p-4">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
            <%!-- Entity selector --%>
            <div>
              <label class="text-xs font-medium opacity-60 mb-1 block">Entity</label>
              <form id="entity-select-form" phx-change="select-entity">
                <select
                  id="entity-select"
                  name="entity_id"
                  class="select select-sm select-bordered w-full font-mono text-xs"
                >
                  <option value="">Select entity...</option>
                  <%= for opt <- @entity_options do %>
                    <option value={opt.id} selected={opt.id == @selected_entity_id}>
                      {short_id(opt.id)} ({opt.type})
                    </option>
                  <% end %>
                </select>
              </form>
            </div>

            <%!-- Attribute selector --%>
            <div>
              <label class="text-xs font-medium opacity-60 mb-1 block">Attribute</label>
              <form id="attr-select-form" phx-change="select-attr">
                <select
                  id="attr-select"
                  name="attr"
                  class="select select-sm select-bordered w-full text-xs"
                  disabled={@available_attrs == []}
                >
                  <option value="">Select attribute...</option>
                  <%= for attr <- @available_attrs do %>
                    <option value={attr.name} selected={attr.name == @selected_attr}>
                      {attr.name} ({attr.count} · {attr.kind})
                    </option>
                  <% end %>
                </select>
              </form>
            </div>

            <%!-- Time range --%>
            <div class="lg:col-span-2">
              <label class="text-xs font-medium opacity-60 mb-1 block">Time Range</label>
              <form id="time-filter-form" phx-submit="apply-time-filter" class="flex gap-2 items-end">
                <select name="timerel" class="select select-sm select-bordered text-xs w-24">
                  <option value="between" selected={@timerel == "between"}>Between</option>
                  <option value="after" selected={@timerel == "after"}>After</option>
                  <option value="before" selected={@timerel == "before"}>Before</option>
                </select>
                <input
                  type="datetime-local"
                  name="time_at"
                  value={@time_at}
                  class="input input-sm input-bordered text-xs flex-1"
                />
                <%= if @timerel == "between" do %>
                  <span class="text-xs opacity-40 px-1">to</span>
                  <input
                    type="datetime-local"
                    name="end_time_at"
                    value={@end_time_at}
                    class="input input-sm input-bordered text-xs flex-1"
                  />
                <% end %>
                <button type="submit" class="btn btn-sm btn-primary btn-outline gap-1">
                  <.icon name="hero-funnel" class="size-3.5" /> Filter
                </button>
              </form>
            </div>
          </div>
        </div>

        <%!-- Chart Area --%>
        <%= if @chart_data do %>
          <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-5">
            <%!-- Chart header --%>
            <div class="flex items-center justify-between mb-4">
              <div>
                <h2 class="font-semibold text-sm">{@chart_data.attr}</h2>
                <p class="text-xs opacity-40 mt-0.5">
                  {short_id(@selected_entity_id)} · {@chart_data.count} data points
                  <span class="badge badge-xs ml-1">
                    {if @chart_data.chart_type == "numeric", do: "numeric", else: "state"}
                  </span>
                </p>
              </div>
              <%= if @chart_data.chart_type == "numeric" do %>
                <div class="flex gap-3">
                  <div class="text-right">
                    <div class="text-xs opacity-40">Min</div>
                    <div class="text-sm font-mono font-semibold">{format_num(@chart_data.min)}</div>
                  </div>
                  <div class="text-right">
                    <div class="text-xs opacity-40">Max</div>
                    <div class="text-sm font-mono font-semibold">{format_num(@chart_data.max)}</div>
                  </div>
                  <div class="text-right">
                    <div class="text-xs opacity-40">Avg</div>
                    <div class="text-sm font-mono font-semibold">
                      {format_num(
                        Enum.sum(Enum.map(@chart_data.points, & &1.y)) / max(@chart_data.count, 1)
                      )}
                    </div>
                  </div>
                </div>
              <% else %>
                <div class="flex gap-2 flex-wrap justify-end">
                  <%= for {val, idx} <- Enum.with_index(@chart_data.unique_values) do %>
                    <span class="badge badge-sm gap-1">
                      <span class={"w-2.5 h-2.5 rounded-sm border border-base-content/20 inline-block state-color-#{idx}"}>
                      </span>
                      {val}
                    </span>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%= if @chart_data.chart_type == "numeric" do %>
              <%!-- Numeric line chart --%>
              <div
                id="temporal-chart"
                phx-hook=".TemporalChart"
                phx-update="ignore"
                data-chart={Jason.encode!(@chart_data)}
                class="w-full"
                style="height: 350px;"
              >
                <canvas id="temporal-chart-canvas"></canvas>
              </div>
            <% else %>
              <%!-- State timeline --%>
              <div
                id="state-timeline"
                phx-hook=".StateTimeline"
                phx-update="ignore"
                data-chart={Jason.encode!(@chart_data)}
                class="w-full"
                style="height: 80px;"
              >
                <canvas id="state-timeline-canvas"></canvas>
              </div>
            <% end %>
          </div>

          <%!-- Data table --%>
          <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-5">
            <h2 class="font-semibold text-sm mb-3 flex items-center gap-2">
              <.icon name="hero-table-cells" class="size-4 opacity-50" /> Raw Data
              <span class="badge badge-xs opacity-50">{@chart_data.count}</span>
            </h2>
            <div class="overflow-x-auto max-h-64 overflow-y-auto">
              <table class="table table-xs table-pin-rows">
                <thead>
                  <tr class="text-xs opacity-50 border-base-300/50">
                    <th>#</th>
                    <th>Timestamp</th>
                    <th>Value</th>
                  </tr>
                </thead>
                <tbody>
                  <%= if @chart_data.chart_type == "numeric" do %>
                    <%= for {point, idx} <- Enum.with_index(@chart_data.points, 1) do %>
                      <tr class="hover:bg-base-300/30 transition-colors border-base-300/30">
                        <td class="text-xs opacity-40">{idx}</td>
                        <td class="font-mono text-xs">{point.x}</td>
                        <td class="font-mono text-xs font-semibold">{format_num(point.y)}</td>
                      </tr>
                    <% end %>
                  <% else %>
                    <%= for {seg, idx} <- Enum.with_index(@chart_data.segments, 1) do %>
                      <tr class="hover:bg-base-300/30 transition-colors border-base-300/30">
                        <td class="text-xs opacity-40">{idx}</td>
                        <td class="font-mono text-xs">{seg.x}</td>
                        <td class="font-mono text-xs font-semibold">{seg.value}</td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% else %>
          <%!-- Empty state --%>
          <div class="card bg-base-200/50 border border-base-300/50 rounded-xl p-12">
            <div class="text-center space-y-3">
              <.icon name="hero-chart-bar" class="size-12 opacity-15 mx-auto" />
              <%= cond do %>
                <% @entity_options == [] -> %>
                  <p class="text-sm opacity-50">No temporal data available</p>
                  <p class="text-xs opacity-30">
                    Use the temporal API (<code class="text-xs">POST /ngsi-ld/v1/temporal/entities</code>) to store historical data
                  </p>
                <% @selected_entity_id == nil -> %>
                  <p class="text-sm opacity-50">Select an entity to view temporal charts</p>
                <% @selected_attr == nil -> %>
                  <p class="text-sm opacity-50">Select an attribute to visualize</p>
                <% true -> %>
                  <p class="text-sm opacity-50">No numeric data points found for this attribute</p>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".TemporalChart">
      export default {
        mounted() {
          this.renderChart()
          this.handleEvent("update-chart", ({chart}) => {
            this.el.dataset.chart = JSON.stringify(chart)
            this.renderChart()
          })
        },

        updated() {
          this.renderChart()
        },

        renderChart() {
          const Chart = window.Chart
          const el = this.el
          const canvas = el.querySelector("canvas")
          const data = JSON.parse(el.dataset.chart || "{}")

          if (!data.points || data.points.length === 0) return

          // Destroy previous chart instance
          if (this._chart) {
            this._chart.destroy()
            this._chart = null
          }

          // Detect theme
          const isDark = document.documentElement.getAttribute("data-theme") !== "light"
          const gridColor = isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.06)"
          const textColor = isDark ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.5)"
          const lineColor = isDark ? "oklch(65% 0.2 277)" : "oklch(55% 0.2 47)"
          const fillColor = isDark ? "rgba(130,100,255,0.08)" : "rgba(200,120,50,0.08)"
          const pointColor = isDark ? "oklch(70% 0.22 277)" : "oklch(60% 0.22 47)"

          const points = data.points.map(p => ({
            x: new Date(p.x),
            y: p.y
          }))

          this._chart = new Chart(canvas, {
            type: "line",
            data: {
              datasets: [{
                label: data.attr,
                data: points,
                borderColor: lineColor,
                backgroundColor: fillColor,
                pointBackgroundColor: pointColor,
                pointBorderColor: "transparent",
                pointRadius: points.length > 100 ? 0 : 3,
                pointHoverRadius: 5,
                borderWidth: 2,
                fill: true,
                tension: 0.3,
                spanGaps: true
              }]
            },
            options: {
              responsive: true,
              maintainAspectRatio: false,
              interaction: { mode: "index", intersect: false },
              plugins: {
                legend: { display: false },
                tooltip: {
                  backgroundColor: isDark ? "rgba(20,20,30,0.95)" : "rgba(255,255,255,0.95)",
                  titleColor: isDark ? "#fff" : "#000",
                  bodyColor: isDark ? "rgba(255,255,255,0.8)" : "rgba(0,0,0,0.7)",
                  borderColor: isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)",
                  borderWidth: 1,
                  padding: 10,
                  cornerRadius: 8,
                  displayColors: false,
                  callbacks: {
                    title: (items) => {
                      const d = new Date(items[0].parsed.x)
                      return d.toLocaleString()
                    },
                    label: (item) => `${data.attr}: ${item.formattedValue}`
                  }
                }
              },
              scales: {
                x: {
                  type: "time",
                  grid: { color: gridColor, drawBorder: false },
                  ticks: { color: textColor, font: { size: 11 }, maxTicksLimit: 10 },
                  border: { display: false }
                },
                y: {
                  grid: { color: gridColor, drawBorder: false },
                  ticks: { color: textColor, font: { size: 11 } },
                  border: { display: false }
                }
              },
              animation: { duration: 600, easing: "easeOutQuart" }
            }
          })

          // Watch for theme changes
          if (!this._observer) {
            this._observer = new MutationObserver(() => this.renderChart())
            this._observer.observe(document.documentElement, {
              attributes: true, attributeFilter: ["data-theme"]
            })
          }
        },

        destroyed() {
          if (this._chart) { this._chart.destroy(); this._chart = null }
          if (this._observer) { this._observer.disconnect(); this._observer = null }
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".StateTimeline">
      const STATE_COLORS = [
        "#3b82f6", "#22c55e", "#f97316", "#a855f7", "#ec4899",
        "#06b6d4", "#eab308", "#ef4444", "#14b8a6", "#8b5cf6"
      ]

      export default {
        mounted() {
          this.renderTimeline()
          this.handleEvent("update-chart", ({chart}) => {
            if (chart.chart_type === "state") {
              this.el.dataset.chart = JSON.stringify(chart)
              this.renderTimeline()
            }
          })
        },

        updated() {
          this.renderTimeline()
        },

        renderTimeline() {
          const el = this.el
          const canvas = el.querySelector("canvas")
          const data = JSON.parse(el.dataset.chart || "{}")

          if (!data.segments || data.segments.length === 0) return

          const ctx = canvas.getContext("2d")
          const dpr = window.devicePixelRatio || 1
          const rect = el.getBoundingClientRect()
          canvas.width = rect.width * dpr
          canvas.height = rect.height * dpr
          ctx.scale(dpr, dpr)
          canvas.style.width = rect.width + "px"
          canvas.style.height = rect.height + "px"

          const w = rect.width
          const h = rect.height
          const pad = { left: 8, right: 8, top: 8, bottom: 20 }
          const barH = h - pad.top - pad.bottom

          const isDark = document.documentElement.getAttribute("data-theme") !== "light"
          const textColor = isDark ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.5)"
          const borderColor = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.2)"

          const colorMap = {}
          ;(data.unique_values || []).forEach((v, i) => {
            colorMap[v] = STATE_COLORS[i % STATE_COLORS.length]
          })

          const times = data.segments.map(s => new Date(s.x).getTime())
          const minT = Math.min(...times)
          const maxT = Math.max(...times)
          const range = maxT - minT || 1

          ctx.clearRect(0, 0, w, h)

          // Draw border around the bar
          ctx.strokeStyle = borderColor
          ctx.lineWidth = 2
          ctx.strokeRect(pad.left, pad.top, w - pad.left - pad.right, barH)

          // Draw segments
          for (let i = 0; i < data.segments.length; i++) {
            const seg = data.segments[i]
            const t0 = new Date(seg.x).getTime()
            const t1 = i < data.segments.length - 1
              ? new Date(data.segments[i + 1].x).getTime()
              : maxT + (range * 0.02)

            const x0 = pad.left + ((t0 - minT) / range) * (w - pad.left - pad.right)
            const x1 = pad.left + ((t1 - minT) / range) * (w - pad.left - pad.right)

            ctx.fillStyle = colorMap[seg.value] || "#666"
            ctx.fillRect(x0, pad.top, Math.max(x1 - x0, 2), barH)

            // Separator line
            if (i > 0) {
              ctx.strokeStyle = isDark ? "rgba(0,0,0,0.4)" : "rgba(255,255,255,0.6)"
              ctx.lineWidth = 1
              ctx.beginPath()
              ctx.moveTo(x0, pad.top)
              ctx.lineTo(x0, pad.top + barH)
              ctx.stroke()
            }
          }

          // Time labels
          ctx.fillStyle = textColor
          ctx.font = "10px monospace"
          ctx.textAlign = "left"
          const startLabel = new Date(minT).toLocaleTimeString()
          ctx.fillText(startLabel, pad.left, h - 4)
          ctx.textAlign = "right"
          const endLabel = new Date(maxT).toLocaleTimeString()
          ctx.fillText(endLabel, w - pad.right, h - 4)

          // Tooltip on hover
          if (!this._tooltipHandler) {
            this._tooltipHandler = (e) => {
              const r = canvas.getBoundingClientRect()
              const mx = e.clientX - r.left
              const barW = w - pad.left - pad.right

              if (mx < pad.left || mx > w - pad.right) {
                canvas.title = ""
                return
              }

              const ratio = (mx - pad.left) / barW
              const hoverT = minT + ratio * range

              let closest = data.segments[0]
              for (let i = data.segments.length - 1; i >= 0; i--) {
                if (new Date(data.segments[i].x).getTime() <= hoverT) {
                  closest = data.segments[i]
                  break
                }
              }
              canvas.title = `${closest.value} — ${new Date(closest.x).toLocaleString()}`
            }
            canvas.addEventListener("mousemove", this._tooltipHandler)
          }

          // Theme watcher
          if (!this._observer) {
            this._observer = new MutationObserver(() => this.renderTimeline())
            this._observer.observe(document.documentElement, {
              attributes: true, attributeFilter: ["data-theme"]
            })
          }
        },

        destroyed() {
          if (this._observer) { this._observer.disconnect(); this._observer = null }
        }
      }
    </script>
    """
  end

  defp format_num(val) when is_float(val), do: :erlang.float_to_binary(val, decimals: 2)
  defp format_num(val) when is_integer(val), do: Integer.to_string(val)
  defp format_num(val), do: to_string(val)
end
