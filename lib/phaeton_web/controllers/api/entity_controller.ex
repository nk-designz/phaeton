defmodule PhaetonWeb.API.EntityController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI
  alias Phaeton.NGSI.Context

  # POST /ngsi-ld/v1/entities
  def create(conn, params) do
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.create_entity(params, tenant) do
      {:ok, entity_id} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/ngsi-ld/v1/entities/#{URI.encode(entity_id)}")
        |> json(%{"id" => entity_id})

      {:error, :already_exists} ->
        problem_details(conn, 409, "AlreadyExists", "Entity already exists.")

      {:error, :bad_request} ->
        problem_details(
          conn,
          400,
          "BadRequestData",
          "Invalid entity data. 'id' and 'type' are required."
        )
    end
  end

  # GET /ngsi-ld/v1/entities
  def index(conn, params) do
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.query_entities(params, tenant) do
      {:ok, entities, meta} ->
        context = conn.assigns[:ngsild_context]

        conn =
          conn
          |> set_content_type(conn)
          |> maybe_add_count_header(meta)
          |> maybe_add_pagination_header(meta)

        entities = maybe_add_context(entities, conn, context)
        json(conn, entities)
    end
  end

  # GET /ngsi-ld/v1/entities/:entity_id
  def show(conn, %{"entity_id" => entity_id}) do
    entity_id = URI.decode(entity_id)
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.get_entity(entity_id, tenant) do
      {:ok, entity} ->
        context = conn.assigns[:ngsild_context]

        conn = set_content_type(conn, conn)

        entity = maybe_add_context(entity, conn, context)
        json(conn, entity)

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity not found: #{entity_id}")
    end
  end

  # DELETE /ngsi-ld/v1/entities/:entity_id
  def delete(conn, %{"entity_id" => entity_id}) do
    entity_id = URI.decode(entity_id)
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.delete_entity(entity_id, tenant) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity not found: #{entity_id}")
    end
  end

  # PATCH /ngsi-ld/v1/entities/:entity_id
  def merge(conn, %{"entity_id" => entity_id} = params) do
    entity_id = URI.decode(entity_id)
    fragment = Map.drop(params, ["entity_id"])
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.merge_entity(entity_id, fragment, tenant) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity not found: #{entity_id}")
    end
  end

  # PUT /ngsi-ld/v1/entities/:entity_id
  def replace(conn, %{"entity_id" => entity_id} = params) do
    entity_id = URI.decode(entity_id)
    entity_data = Map.drop(params, ["entity_id"])
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.replace_entity(entity_id, entity_data, tenant) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity not found: #{entity_id}")

      {:error, :bad_request} ->
        problem_details(conn, 400, "BadRequestData", "Invalid entity data. 'type' is required.")
    end
  end

  # POST /ngsi-ld/v1/entities/:entity_id/attrs
  def append_attrs(conn, %{"entity_id" => entity_id} = params) do
    entity_id = URI.decode(entity_id)
    no_overwrite = conn.query_params["options"] == "noOverwrite"
    attrs = Map.drop(params, ["entity_id"])
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.append_attrs(entity_id, attrs, [no_overwrite: no_overwrite], tenant) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity not found: #{entity_id}")
    end
  end

  # PATCH /ngsi-ld/v1/entities/:entity_id/attrs
  def update_attrs(conn, %{"entity_id" => entity_id} = params) do
    entity_id = URI.decode(entity_id)
    attrs = Map.drop(params, ["entity_id"])
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.update_attrs(entity_id, attrs, tenant) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity not found: #{entity_id}")
    end
  end

  # PATCH /ngsi-ld/v1/entities/:entity_id/attrs/:attr_id
  def update_attr(conn, %{"entity_id" => entity_id, "attr_id" => attr_id} = params) do
    entity_id = URI.decode(entity_id)
    attr_id = URI.decode(attr_id)
    fragment = Map.drop(params, ["entity_id", "attr_id"])
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.update_attr(entity_id, attr_id, fragment, tenant) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity or attribute not found.")
    end
  end

  # DELETE /ngsi-ld/v1/entities/:entity_id/attrs/:attr_id
  def delete_attr(conn, %{"entity_id" => entity_id, "attr_id" => attr_id}) do
    entity_id = URI.decode(entity_id)
    attr_id = URI.decode(attr_id)
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.delete_attr(entity_id, attr_id, tenant) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity or attribute not found.")
    end
  end

  # PUT /ngsi-ld/v1/entities/:entity_id/attrs/:attr_id
  def replace_attr(conn, %{"entity_id" => entity_id, "attr_id" => attr_id} = params) do
    entity_id = URI.decode(entity_id)
    attr_id = URI.decode(attr_id)
    fragment = Map.drop(params, ["entity_id", "attr_id"])
    tenant = conn.assigns[:ngsild_tenant]

    case NGSI.replace_attr(entity_id, attr_id, fragment, tenant) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Entity or attribute not found.")
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

  defp set_content_type(conn, original_conn) do
    accept = get_req_header(original_conn, "accept") |> List.first("")

    if String.contains?(accept, "application/ld+json") do
      put_resp_header(conn, "content-type", "application/ld+json")
    else
      put_resp_header(conn, "content-type", "application/json")
    end
  end

  defp maybe_add_count_header(conn, meta) do
    if meta.count do
      put_resp_header(conn, "ngsild-results-count", to_string(meta.total_count))
    else
      conn
    end
  end

  defp maybe_add_pagination_header(conn, meta) do
    if meta.offset + meta.limit < meta.total_count do
      next_offset = meta.offset + meta.limit
      next_url = "/ngsi-ld/v1/entities?offset=#{next_offset}&limit=#{meta.limit}"
      put_resp_header(conn, "link", "<#{next_url}>; rel=\"next\"")
    else
      conn
    end
  end

  # For application/ld+json, @context is embedded inline
  # For application/json, @context is in Link header only (don't embed)
  defp maybe_add_context(data, conn, context) do
    content_type =
      case get_resp_header(conn, "content-type") do
        [ct | _] -> ct
        _ -> "application/json"
      end

    if String.contains?(content_type, "ld+json") do
      case data do
        entities when is_list(entities) -> Context.add_context_to_entities(entities, context)
        entity when is_map(entity) -> Context.add_context_to_entity(entity, context)
      end
    else
      data
    end
  end
end
