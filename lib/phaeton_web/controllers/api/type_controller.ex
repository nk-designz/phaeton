defmodule PhaetonWeb.API.TypeController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI

  # GET /ngsi-ld/v1/types
  def index(conn, _params) do
    {:ok, types} = NGSI.get_types()

    result = %{
      "id" =>
        "urn:ngsi-ld:EntityTypeList:" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower),
      "type" => "EntityTypeList",
      "typeList" => types
    }

    json(conn, result)
  end

  # GET /ngsi-ld/v1/types/:type
  def show(conn, %{"type" => type}) do
    type = URI.decode(type)

    case NGSI.get_type_info(type) do
      {:ok, info} ->
        result = %{
          "id" =>
            "urn:ngsi-ld:EntityTypeInfo:" <>
              Base.encode16(:crypto.strong_rand_bytes(4), case: :lower),
          "type" => "EntityTypeInfo",
          "typeName" => type,
          "entityCount" => info.entity_count,
          "attributeDetails" => info.attribute_details
        }

        json(conn, result)
    end
  end
end
