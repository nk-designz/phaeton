defmodule PhaetonWeb.API.EntityMapController do
  use PhaetonWeb, :controller

  # Entity maps are a grouping construct over entity queries.
  # For now, we store them in-memory or as a lightweight store.

  # GET /ngsi-ld/v1/entityMap/:entity_map_id
  def show(conn, %{"entity_map_id" => id}) do
    id = URI.decode(id)
    # Entity maps are created as side effects of queries with entityMap option.
    # Return not found for now if no map exists.
    problem_details(conn, 404, "ResourceNotFound", "Entity map not found: #{id}")
  end

  # PATCH /ngsi-ld/v1/entityMap/:entity_map_id
  def update(conn, %{"entity_map_id" => id}) do
    id = URI.decode(id)
    problem_details(conn, 404, "ResourceNotFound", "Entity map not found: #{id}")
  end

  # DELETE /ngsi-ld/v1/entityMap/:entity_map_id
  def delete(conn, %{"entity_map_id" => id}) do
    id = URI.decode(id)
    problem_details(conn, 404, "ResourceNotFound", "Entity map not found: #{id}")
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
