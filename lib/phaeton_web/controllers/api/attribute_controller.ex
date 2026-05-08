defmodule PhaetonWeb.API.AttributeController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI

  # GET /ngsi-ld/v1/attributes
  def index(conn, _params) do
    {:ok, attrs} = NGSI.get_attributes()

    result = %{
      "id" =>
        "urn:ngsi-ld:AttributeList:" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower),
      "type" => "AttributeList",
      "attributeList" => attrs
    }

    json(conn, result)
  end

  # GET /ngsi-ld/v1/attributes/:attr_id
  def show(conn, %{"attr_id" => attr_id}) do
    attr_id = URI.decode(attr_id)

    case NGSI.get_attribute_info(attr_id) do
      {:ok, info} ->
        result = %{
          "id" =>
            "urn:ngsi-ld:Attribute:" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower),
          "type" => "Attribute",
          "attributeName" => attr_id,
          "attributeCount" => info.attribute_count,
          "attributeTypes" => info.attribute_types,
          "typeNames" => info.type_names
        }

        json(conn, result)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{
          "type" => "https://uri.etsi.org/ngsi-ld/errors/ResourceNotFound",
          "title" => "ResourceNotFound",
          "status" => 404,
          "detail" => "Attribute not found: #{attr_id}"
        })
    end
  end
end
