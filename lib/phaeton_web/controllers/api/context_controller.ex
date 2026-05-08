defmodule PhaetonWeb.API.ContextController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI.Context

  # POST /ngsi-ld/v1/jsonldContexts
  def create(conn, params) do
    case Context.create_context(params) do
      {:ok, doc} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/ngsi-ld/v1/jsonldContexts/#{URI.encode(doc.id)}")
        |> json(%{"id" => doc.id})

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> json(%{
          "type" => "https://uri.etsi.org/ngsi-ld/errors/BadRequestData",
          "title" => "BadRequestData",
          "status" => 400,
          "detail" => "Invalid context data: #{inspect(changeset.errors)}"
        })
    end
  end

  # GET /ngsi-ld/v1/jsonldContexts
  def index(conn, params) do
    details = Map.get(params, "details", "false") == "true"
    kind = Map.get(params, "kind")

    {:ok, contexts} = Context.list_contexts(details: details, kind: kind)
    json(conn, contexts)
  end

  # GET /ngsi-ld/v1/jsonldContexts/:context_id
  def show(conn, %{"context_id" => id}) do
    case Context.get_context(URI.decode(id)) do
      {:ok, body} ->
        json(conn, body)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{
          "type" => "https://uri.etsi.org/ngsi-ld/errors/ResourceNotFound",
          "title" => "ResourceNotFound",
          "status" => 404,
          "detail" => "Context not found."
        })
    end
  end

  # DELETE /ngsi-ld/v1/jsonldContexts/:context_id
  def delete(conn, %{"context_id" => id}) do
    case Context.delete_context(URI.decode(id)) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{
          "type" => "https://uri.etsi.org/ngsi-ld/errors/ResourceNotFound",
          "title" => "ResourceNotFound",
          "status" => 404,
          "detail" => "Context not found."
        })
    end
  end
end
