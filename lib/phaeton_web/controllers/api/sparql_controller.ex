defmodule PhaetonWeb.API.SparqlController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI.Sparql

  @doc """
  POST /ngsi-ld/v1/sparql
  Execute a SPARQL query against the triple store.

  Accepts the query in the request body as plain text (Content-Type: application/sparql-query)
  or as a JSON object with a "query" field.
  """
  def query(conn, params) do
    query_string = extract_query(conn, params)

    cond do
      is_nil(query_string) or query_string == "" ->
        problem_details(
          conn,
          400,
          "BadRequestData",
          "Missing SPARQL query. Send as request body or {\"query\": \"...\"}."
        )

      String.length(query_string) > 50_000 ->
        problem_details(conn, 400, "BadRequestData", "Query too large (max 50KB).")

      true ->
        case Sparql.execute(query_string) do
          {:ok, result} ->
            conn
            |> put_status(200)
            |> json(Sparql.result_to_json(result))

          {:error, reason} ->
            problem_details(conn, 400, "BadRequestData", "SPARQL error: #{reason}")
        end
    end
  end

  defp extract_query(conn, params) do
    cond do
      Map.has_key?(params, "query") ->
        params["query"]

      true ->
        case Plug.Conn.read_body(conn) do
          {:ok, body, _conn} when body != "" -> body
          _ -> nil
        end
    end
  end

  defp problem_details(conn, status, type, detail) do
    conn
    |> put_status(status)
    |> json(%{
      "type" => "https://uri.etsi.org/ngsi-ld/errors/#{type}",
      "title" => type,
      "status" => status,
      "detail" => detail
    })
  end
end
