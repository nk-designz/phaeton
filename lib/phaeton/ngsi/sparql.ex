defmodule Phaeton.NGSI.Sparql do
  @moduledoc """
  SPARQL query execution against the RDF triple store.
  Loads all triples into an RDF.Graph and executes SPARQL queries using the sparql library.
  """

  alias Phaeton.Repo
  alias Phaeton.Store
  alias Phaeton.Store.Triple

  @max_results 10_000

  @doc """
  Execute a SPARQL query string against the full triple store.
  Returns `{:ok, result}` or `{:error, reason}`.

  The result depends on the query type:
  - SELECT: `%SPARQL.Query.Result{variables: [...], results: [%{...}]}`
  - ASK: `%SPARQL.Query.Result{results: true | false}`
  - CONSTRUCT/DESCRIBE: `%RDF.Graph{}`
  """
  def execute(query_string) when is_binary(query_string) do
    execute(query_string, :all)
  end

  @doc """
  Execute a SPARQL query scoped to a tenant.
  - `:all`   — query all triples (default, admin)
  - `nil`    — only the default (no-prefix) tenant
  - binary   — only triples for that named tenant
  """
  def execute(query_string, tenant) when is_binary(query_string) do
    with {:ok, query} <- parse_query(query_string),
         graph <- load_graph(tenant) do
      case SPARQL.execute_query(graph, query) do
        %SPARQL.Query.Result{} = result -> {:ok, result}
        %RDF.Graph{} = graph -> {:ok, graph}
        other -> {:ok, other}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Parse a SPARQL query string into a query struct.
  """
  def parse_query(query_string) do
    case SPARQL.query(query_string) do
      %SPARQL.Query{} = query -> {:ok, query}
      {:error, reason} -> {:error, "SPARQL parse error: #{inspect(reason)}"}
      other -> {:error, "Unexpected parse result: #{inspect(other)}"}
    end
  rescue
    e -> {:error, "SPARQL parse error: #{Exception.message(e)}"}
  end

  @doc """
  Format SPARQL results as a JSON-serializable map.
  """
  def result_to_json(%SPARQL.Query.Result{variables: vars, results: results})
      when is_list(results) do
    %{
      "type" => "select",
      "variables" => Enum.map(vars, &to_string/1),
      "results" =>
        results
        |> Enum.take(@max_results)
        |> Enum.map(fn row ->
          Map.new(row, fn {var, term} ->
            {to_string(var), rdf_term_to_json(term)}
          end)
        end),
      "count" => length(results)
    }
  end

  def result_to_json(%SPARQL.Query.Result{results: bool}) when is_boolean(bool) do
    %{"type" => "ask", "result" => bool}
  end

  def result_to_json(%RDF.Graph{} = graph) do
    triples =
      graph
      |> Enum.take(@max_results)
      |> Enum.map(fn {s, p, o} ->
        %{
          "subject" => to_string(s),
          "predicate" => to_string(p),
          "object" => rdf_term_to_json(o)
        }
      end)

    %{"type" => "graph", "triples" => triples, "count" => Enum.count(graph)}
  end

  def result_to_json(other) do
    %{"type" => "unknown", "raw" => inspect(other)}
  end

  @doc """
  Returns a list of example SPARQL queries relevant to NGSI-LD data.
  """
  def example_queries do
    [
      %{
        name: "All entity types",
        description: "List all distinct entity types in the store",
        query: """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

        SELECT DISTINCT ?type WHERE {
          ?entity rdf:type ?type .
        }
        ORDER BY ?type
        """
      },
      %{
        name: "All entities",
        description: "List all entities with their types",
        query: """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

        SELECT ?entity ?type WHERE {
          ?entity rdf:type ?type .
        }
        ORDER BY ?type ?entity
        """
      },
      %{
        name: "Entity properties",
        description: "Get all property values across entities",
        query: """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

        SELECT ?entity ?prop ?value WHERE {
          ?entity ?prop ?value .
          FILTER(isIRI(?entity))
          FILTER(isLiteral(?value))
          FILTER(?prop != rdf:type)
        }
        LIMIT 100
        """
      },
      %{
        name: "Relationships",
        description: "Find all relationships between entities",
        query: """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

        SELECT DISTINCT ?source ?rel ?target WHERE {
          ?source ?rel ?target .
          FILTER(isIRI(?source))
          FILTER(isIRI(?target))
          FILTER(isIRI(?rel))
          FILTER(?rel != rdf:type)
        }
        """
      },
      %{
        name: "Connected entity types",
        description: "Show which entity types are connected and through what relationship",
        query: """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

        SELECT DISTINCT ?sourceType ?rel ?targetType WHERE {
          ?source rdf:type ?sourceType .
          ?target rdf:type ?targetType .
          ?source ?rel ?target .
          FILTER(isIRI(?rel))
          FILTER(?rel != rdf:type)
        }
        ORDER BY ?sourceType ?rel ?targetType
        """
      }
    ]
  end

  # Load triples from SQLite into an RDF.Graph, filtered by tenant.
  defp load_graph(:all) do
    triples = Repo.all(Triple)
    Store.triples_to_graph(triples)
  end

  defp load_graph(nil) do
    import Ecto.Query
    triples = Triple |> where([t], t.graph_name == t.subject) |> Repo.all()
    Store.triples_to_graph(triples)
  end

  defp load_graph(tenant) when is_binary(tenant) do
    import Ecto.Query

    triples =
      Triple |> where([t], fragment("? LIKE ?", t.graph_name, ^"#{tenant}:%")) |> Repo.all()

    Store.triples_to_graph(triples)
  end

  defp rdf_term_to_json(%RDF.IRI{} = iri) do
    %{"type" => "uri", "value" => to_string(iri)}
  end

  defp rdf_term_to_json(%RDF.BlankNode{} = bnode) do
    %{"type" => "bnode", "value" => to_string(bnode)}
  end

  defp rdf_term_to_json(%RDF.Literal{} = lit) do
    base = %{
      "type" => "literal",
      "value" => RDF.Literal.lexical(lit),
      "datatype" => to_string(RDF.Literal.datatype_id(lit))
    }

    case RDF.Literal.language(lit) do
      nil -> base
      lang -> Map.put(base, "xml:lang", to_string(lang))
    end
  end

  defp rdf_term_to_json(other) do
    %{"type" => "unknown", "value" => inspect(other)}
  end
end
