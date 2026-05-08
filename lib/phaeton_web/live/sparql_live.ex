defmodule PhaetonWeb.SparqlLive do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI.Sparql

  @impl true
  def mount(_params, _session, socket) do
    examples = Sparql.example_queries()

    socket =
      socket
      |> assign(:page_title, "SPARQL")
      |> assign(:query, "")
      |> assign(:result, nil)
      |> assign(:error, nil)
      |> assign(:executing, false)
      |> assign(:elapsed_ms, nil)
      |> assign(:examples, examples)
      |> assign(:history, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("execute", %{"query" => query}, socket) do
    query = String.trim(query)
    tenant = socket.assigns.current_scope && socket.assigns.current_scope.active_tenant
    tenant = tenant || :all

    if query == "" do
      {:noreply, assign(socket, :error, "Please enter a SPARQL query.")}
    else
      start = System.monotonic_time(:millisecond)

      case Sparql.execute(query, tenant) do
        {:ok, result} ->
          elapsed = System.monotonic_time(:millisecond) - start
          json_result = Sparql.result_to_json(result)

          history =
            [%{query: query, timestamp: DateTime.utc_now()} | socket.assigns.history]
            |> Enum.take(20)

          {:noreply,
           socket
           |> assign(:query, query)
           |> assign(:result, json_result)
           |> assign(:error, nil)
           |> assign(:elapsed_ms, elapsed)
           |> assign(:history, history)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:query, query)
           |> assign(:result, nil)
           |> assign(:error, reason)
           |> assign(:elapsed_ms, nil)}
      end
    end
  end

  def handle_event("load-example", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    example = Enum.at(socket.assigns.examples, index)

    if example do
      {:noreply, assign(socket, :query, String.trim(example.query))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("load-history", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    entry = Enum.at(socket.assigns.history, index)

    if entry do
      {:noreply, assign(socket, :query, entry.query)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear", _, socket) do
    {:noreply,
     socket
     |> assign(:query, "")
     |> assign(:result, nil)
     |> assign(:error, nil)
     |> assign(:elapsed_ms, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:sparql} current_scope={@current_scope}>
      <div class="space-y-4">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold tracking-tight heading-gradient">SPARQL Query</h1>
            <p class="text-sm opacity-60 mt-0.5">
              Execute SPARQL queries against the RDF triple store
            </p>
          </div>
          <div class="flex items-center gap-2">
            <span class="badge badge-sm font-mono">POST /ngsi-ld/v1/sparql</span>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-4 gap-4">
          <%!-- Sidebar: Examples & History --%>
          <div class="lg:col-span-1 space-y-4">
            <%!-- Examples --%>
            <div class="card-glass">
              <div class="px-4 py-3 border-b-2 border-nb">
                <h3 class="text-sm font-bold flex items-center gap-1.5">
                  <.icon name="hero-light-bulb" class="size-4 text-warning" /> Examples
                </h3>
              </div>
              <ul class="p-2 space-y-0.5">
                <%= for {example, idx} <- Enum.with_index(@examples) do %>
                  <li>
                    <button
                      phx-click="load-example"
                      phx-value-index={idx}
                      class="w-full text-left px-3 py-2 rounded-[5px] hover:bg-primary/20 transition-colors text-xs group border-2 border-transparent hover:border-nb"
                    >
                      <div class="font-bold group-hover:text-primary transition-colors">
                        {example.name}
                      </div>
                      <div class="opacity-50 mt-0.5">{example.description}</div>
                    </button>
                  </li>
                <% end %>
              </ul>
            </div>

            <%!-- History --%>
            <%= if @history != [] do %>
              <div class="card-glass">
                <div class="px-4 py-3 border-b-2 border-nb">
                  <h3 class="text-sm font-bold flex items-center gap-1.5">
                    <.icon name="hero-clock" class="size-4" /> History
                  </h3>
                </div>
                <ul class="p-2 space-y-0.5 max-h-48 overflow-y-auto">
                  <%= for {entry, idx} <- Enum.with_index(@history) do %>
                    <li>
                      <button
                        phx-click="load-history"
                        phx-value-index={idx}
                        class="w-full text-left px-3 py-2 rounded-[5px] hover:bg-primary/20 transition-colors text-xs group border-2 border-transparent hover:border-nb"
                      >
                        <div class="font-mono truncate opacity-70 group-hover:text-primary transition-colors">
                          {String.slice(entry.query, 0, 60)}...
                        </div>
                        <div class="opacity-40 text-[10px] font-bold mt-0.5">
                          {Calendar.strftime(entry.timestamp, "%H:%M:%S")}
                        </div>
                      </button>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% end %>
          </div>

          <%!-- Main: Editor & Results --%>
          <div class="lg:col-span-3 space-y-4">
            <%!-- Query Editor --%>
            <form phx-submit="execute" class="card-glass">
              <div class="px-4 py-3 border-b-2 border-nb flex items-center justify-between">
                <h3 class="text-sm font-bold flex items-center gap-1.5">
                  <.icon name="hero-command-line" class="size-4 text-primary" /> Query Editor
                </h3>
                <div class="flex items-center gap-2">
                  <button type="button" phx-click="clear" class="btn btn-xs btn-ghost gap-1">
                    <.icon name="hero-x-mark" class="size-3.5" /> Clear
                  </button>
                  <button type="submit" class="btn btn-xs btn-primary gap-1">
                    <.icon name="hero-play" class="size-3.5" /> Run Query
                  </button>
                </div>
              </div>
              <div class="p-3">
                <textarea
                  name="query"
                  value={@query}
                  rows="10"
                  placeholder="SELECT ?s ?p ?o WHERE {\n  ?s ?p ?o .\n} LIMIT 10"
                  class="textarea w-full font-mono text-sm leading-relaxed bg-base-100 resize-y min-h-[200px]"
                  spellcheck="false"
                >{@query}</textarea>
              </div>
            </form>

            <%!-- Error --%>
            <%= if @error do %>
              <div class="card bg-error/20 p-4">
                <div class="flex items-start gap-3">
                  <.icon name="hero-exclamation-triangle" class="size-5 text-error shrink-0 mt-0.5" />
                  <div>
                    <div class="font-bold text-sm text-error">Query Error</div>
                    <div class="text-xs opacity-70 mt-1 font-mono whitespace-pre-wrap">{@error}</div>
                  </div>
                </div>
              </div>
            <% end %>

            <%!-- Results --%>
            <%= if @result do %>
              <div class="card-glass">
                <div class="px-4 py-3 border-b-2 border-nb flex items-center justify-between">
                  <h3 class="text-sm font-bold flex items-center gap-1.5">
                    <.icon name="hero-table-cells" class="size-4 text-secondary" /> Results
                    <span class="badge badge-sm font-mono">
                      {@result["count"]} row{if @result["count"] != 1, do: "s"}
                    </span>
                  </h3>
                  <div class="flex items-center gap-3 text-xs">
                    <%= if @elapsed_ms do %>
                      <span class="font-mono font-bold opacity-60">{@elapsed_ms}ms</span>
                    <% end %>
                    <span class="badge badge-sm badge-primary uppercase">{@result["type"]}</span>
                  </div>
                </div>

                <div class="p-0 overflow-x-auto">
                  <%= case @result["type"] do %>
                    <% "select" -> %>
                      <.select_table variables={@result["variables"]} results={@result["results"]} />
                    <% "ask" -> %>
                      <div class="p-6 text-center">
                        <div class={[
                          "text-4xl font-bold",
                          if(@result["result"], do: "text-success", else: "text-error")
                        ]}>
                          {if @result["result"], do: "TRUE", else: "FALSE"}
                        </div>
                      </div>
                    <% "graph" -> %>
                      <.graph_table triples={@result["triples"]} />
                    <% _ -> %>
                      <div class="p-4">
                        <pre class="text-xs font-mono opacity-60">{Jason.encode!(@result, pretty: true)}</pre>
                      </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp select_table(assigns) do
    ~H"""
    <table class="table table-sm w-full">
      <thead>
        <tr>
          <%= for var <- @variables do %>
            <th class="font-mono text-xs font-bold">?{var}</th>
          <% end %>
        </tr>
      </thead>
      <tbody>
        <%= for row <- @results do %>
          <tr class="hover:bg-primary/10 transition-colors">
            <%= for var <- @variables do %>
              <td class="font-mono text-xs max-w-xs truncate">
                <.rdf_value term={row[var]} />
              </td>
            <% end %>
          </tr>
        <% end %>
        <%= if @results == [] do %>
          <tr>
            <td colspan={length(@variables)} class="text-center opacity-40 py-8 text-sm font-bold">
              No results
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp graph_table(assigns) do
    ~H"""
    <table class="table table-sm w-full">
      <thead>
        <tr>
          <th class="font-mono text-xs font-bold">Subject</th>
          <th class="font-mono text-xs font-bold">Predicate</th>
          <th class="font-mono text-xs font-bold">Object</th>
        </tr>
      </thead>
      <tbody>
        <%= for triple <- @triples do %>
          <tr class="hover:bg-primary/10 transition-colors">
            <td class="font-mono text-xs max-w-xs truncate">{shorten_uri(triple["subject"])}</td>
            <td class="font-mono text-xs max-w-xs truncate">{shorten_uri(triple["predicate"])}</td>
            <td class="font-mono text-xs max-w-xs truncate">
              <.rdf_value term={triple["object"]} />
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp rdf_value(%{term: nil} = assigns), do: ~H|<span class="opacity-30">—</span>|

  defp rdf_value(%{term: %{"type" => "uri", "value" => value}} = assigns) do
    assigns = assign(assigns, :short, shorten_uri(value))

    ~H"""
    <span class="text-primary/80" title={@term["value"]}>{@short}</span>
    """
  end

  defp rdf_value(%{term: %{"type" => "literal", "value" => _value}} = assigns) do
    ~H"""
    <span class="text-success/80">"{@term["value"]}"</span>
    <span
      :if={@term["datatype"] && @term["datatype"] != "http://www.w3.org/2001/XMLSchema#string"}
      class="text-[10px] opacity-30 ml-1"
    >
      ^^{shorten_uri(@term["datatype"])}
    </span>
    <span :if={@term["xml:lang"]} class="text-[10px] opacity-30 ml-1">@{@term["xml:lang"]}</span>
    """
  end

  defp rdf_value(%{term: %{"type" => "bnode", "value" => _value}} = assigns) do
    ~H"""
    <span class="opacity-50">_:{@term["value"]}</span>
    """
  end

  defp rdf_value(assigns) do
    ~H"""
    <span class="opacity-40">{inspect(@term)}</span>
    """
  end

  @prefixes %{
    "http://www.w3.org/1999/02/22-rdf-syntax-ns#" => "rdf:",
    "http://www.w3.org/2000/01/rdf-schema#" => "rdfs:",
    "http://www.w3.org/2001/XMLSchema#" => "xsd:",
    "http://www.w3.org/2002/07/owl#" => "owl:",
    "https://uri.etsi.org/ngsi-ld/" => "ngsild:",
    "http://www.w3.org/ns/json-ld#" => "jsonld:"
  }

  defp shorten_uri(uri) when is_binary(uri) do
    Enum.find_value(@prefixes, uri, fn {full, prefix} ->
      if String.starts_with?(uri, full) do
        prefix <> String.replace_prefix(uri, full, "")
      end
    end)
  end

  defp shorten_uri(other), do: other
end
