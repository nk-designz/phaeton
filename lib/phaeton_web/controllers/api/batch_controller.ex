defmodule PhaetonWeb.API.BatchController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI

  # POST /ngsi-ld/v1/entityOperations/create
  def create(conn, %{"_json" => entities}) when is_list(entities) do
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.batch_create(entities, tenant) do
      {:ok, result} ->
        if result["errors"] == [] do
          conn |> put_status(:created) |> json(result["success"])
        else
          conn |> put_status(207) |> json(result)
        end
    end
  end

  def create(conn, _params) do
    problem_details(conn, 400, "BadRequestData", "Request body must be a JSON array of entities.")
  end

  # POST /ngsi-ld/v1/entityOperations/upsert
  def upsert(conn, %{"_json" => entities}) when is_list(entities) do
    tenant = conn.assigns[:ngsild_tenant]

    mode =
      case conn.query_params["options"] do
        "update" -> :update
        _ -> :replace
      end

    case NGSI.batch_upsert(entities, [mode: mode], tenant) do
      {:ok, result} ->
        if result["errors"] == [] do
          conn |> put_status(:created) |> json(result["success"])
        else
          conn |> put_status(207) |> json(result)
        end
    end
  end

  def upsert(conn, _params) do
    problem_details(conn, 400, "BadRequestData", "Request body must be a JSON array of entities.")
  end

  # POST /ngsi-ld/v1/entityOperations/delete
  def delete(conn, %{"_json" => entity_ids}) when is_list(entity_ids) do
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.batch_delete(entity_ids, tenant) do
      {:ok, result} ->
        if result["errors"] == [] do
          send_resp(conn, 204, "")
        else
          conn |> put_status(207) |> json(result)
        end
    end
  end

  def delete(conn, _params) do
    problem_details(
      conn,
      400,
      "BadRequestData",
      "Request body must be a JSON array of entity IDs."
    )
  end

  # POST /ngsi-ld/v1/entityOperations/update
  def update(conn, %{"_json" => entities}) when is_list(entities) do
    tenant = conn.assigns[:ngsild_tenant]

    results =
      Enum.map(entities, fn entity ->
        entity_id = Map.get(entity, "id")

        case NGSI.update_attrs(entity_id, Map.drop(entity, ["id", "type"]), tenant) do
          :ok -> {:ok, entity_id}
          {:error, reason} -> {:error, entity_id || "unknown", reason}
        end
      end)

    success = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(fn {:ok, id} -> id end)

    errors =
      Enum.filter(results, &match?({:error, _, _}, &1))
      |> Enum.map(fn {:error, id, reason} -> %{"entityId" => id, "error" => to_string(reason)} end)

    if errors == [] do
      send_resp(conn, 204, "")
    else
      conn |> put_status(207) |> json(%{"success" => success, "errors" => errors})
    end
  end

  def update(conn, _params) do
    problem_details(conn, 400, "BadRequestData", "Request body must be a JSON array of entities.")
  end

  # POST /ngsi-ld/v1/entityOperations/merge
  def merge(conn, %{"_json" => entities}) when is_list(entities) do
    tenant = conn.assigns[:ngsild_tenant]

    results =
      Enum.map(entities, fn entity ->
        entity_id = Map.get(entity, "id")

        case NGSI.merge_entity(entity_id, Map.drop(entity, ["id", "type"]), tenant) do
          :ok -> {:ok, entity_id}
          {:error, reason} -> {:error, entity_id || "unknown", reason}
        end
      end)

    success = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(fn {:ok, id} -> id end)

    errors =
      Enum.filter(results, &match?({:error, _, _}, &1))
      |> Enum.map(fn {:error, id, reason} -> %{"entityId" => id, "error" => to_string(reason)} end)

    if errors == [] do
      send_resp(conn, 204, "")
    else
      conn |> put_status(207) |> json(%{"success" => success, "errors" => errors})
    end
  end

  def merge(conn, _params) do
    problem_details(conn, 400, "BadRequestData", "Request body must be a JSON array of entities.")
  end

  # POST /ngsi-ld/v1/entityOperations/query
  def query(conn, params) do
    query_params = Map.merge(conn.query_params, params)

    case NGSI.query_entities(query_params) do
      {:ok, entities, _meta} ->
        json(conn, entities)
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
