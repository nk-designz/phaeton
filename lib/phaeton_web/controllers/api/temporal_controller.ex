defmodule PhaetonWeb.API.TemporalController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI.Temporal

  # POST /ngsi-ld/v1/temporal/entities
  def create(conn, params) do
    case Temporal.upsert_temporal(params) do
      {:ok, entity_id} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/ngsi-ld/v1/temporal/entities/#{URI.encode(entity_id)}")
        |> json(%{"id" => entity_id})

      {:error, :bad_request} ->
        problem_details(conn, 400, "BadRequestData", "Invalid temporal entity data.")
    end
  end

  # GET /ngsi-ld/v1/temporal/entities
  def index(conn, params) do
    case Temporal.query_temporal(params) do
      {:ok, entities} ->
        json(conn, entities)
    end
  end

  # GET /ngsi-ld/v1/temporal/entities/:entity_id
  def show(conn, %{"entity_id" => entity_id} = params) do
    entity_id = URI.decode(entity_id)
    query_params = Map.drop(params, ["entity_id"])

    case Temporal.retrieve_temporal(entity_id, query_params) do
      {:ok, entity} ->
        json(conn, entity)

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Temporal entity not found: #{entity_id}")
    end
  end

  # DELETE /ngsi-ld/v1/temporal/entities/:entity_id
  def delete(conn, %{"entity_id" => entity_id}) do
    entity_id = URI.decode(entity_id)

    case Temporal.delete_temporal(entity_id) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Temporal entity not found: #{entity_id}")
    end
  end

  # POST /ngsi-ld/v1/temporal/entities/:entity_id/attrs
  def append_attrs(conn, %{"entity_id" => entity_id} = params) do
    entity_id = URI.decode(entity_id)
    attrs = Map.drop(params, ["entity_id"])

    case Temporal.append_temporal_attrs(entity_id, attrs) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :bad_request} ->
        problem_details(conn, 400, "BadRequestData", "Invalid temporal attribute data.")
    end
  end

  # DELETE /ngsi-ld/v1/temporal/entities/:entity_id/attrs/:attr_id
  def delete_attr(conn, %{"entity_id" => entity_id, "attr_id" => attr_id} = params) do
    entity_id = URI.decode(entity_id)
    attr_id = URI.decode(attr_id)

    case Temporal.delete_temporal_attr(entity_id, attr_id, params) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Temporal attribute not found.")
    end
  end

  # PATCH /ngsi-ld/v1/temporal/entities/:entity_id/attrs/:attr_id/:instance_id
  def update_attr_instance(
        conn,
        %{"entity_id" => entity_id, "attr_id" => attr_id, "instance_id" => instance_id} = params
      ) do
    entity_id = URI.decode(entity_id)
    attr_id = URI.decode(attr_id)
    instance_id = URI.decode(instance_id)
    fragment = Map.drop(params, ["entity_id", "attr_id", "instance_id"])

    case Temporal.update_temporal_attr_instance(entity_id, attr_id, instance_id, fragment) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Temporal attribute instance not found.")
    end
  end

  # DELETE /ngsi-ld/v1/temporal/entities/:entity_id/attrs/:attr_id/:instance_id
  def delete_attr_instance(conn, %{
        "entity_id" => entity_id,
        "attr_id" => attr_id,
        "instance_id" => instance_id
      }) do
    entity_id = URI.decode(entity_id)
    attr_id = URI.decode(attr_id)
    instance_id = URI.decode(instance_id)

    case Temporal.delete_temporal_attr_instance(entity_id, attr_id, instance_id) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Temporal attribute instance not found.")
    end
  end

  # POST /ngsi-ld/v1/temporal/entityOperations/query
  def query_batch(conn, params) do
    query_params = Map.merge(conn.query_params, params)

    case Temporal.query_temporal(query_params) do
      {:ok, entities} ->
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
