defmodule PhaetonWeb.API.TypeControllerTest do
  use PhaetonWeb.ConnCase

  defp unique_id(label) do
    hex = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "urn:ngsi-ld:Sensor:#{label}_#{hex}"
  end

  setup %{conn: conn} do
    conn = conn |> put_req_header("content-type", "application/json") |> put_api_token()

    # Create a test entity so types/attributes exist
    id = unique_id("typetest")

    entity = %{
      "id" => id,
      "type" => "Sensor",
      "temperature" => %{"type" => "Property", "value" => 22.5}
    }

    post(conn, "/ngsi-ld/v1/entities", entity)

    {:ok, conn: conn, entity_id: id}
  end

  describe "GET /ngsi-ld/v1/types" do
    test "returns EntityTypeList", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/types")
      body = json_response(conn, 200)

      assert body["type"] == "EntityTypeList"
      assert is_list(body["typeList"])
      assert "Sensor" in body["typeList"]
    end
  end

  describe "GET /ngsi-ld/v1/types/:type" do
    test "returns EntityTypeInfo with details", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/types/Sensor")
      body = json_response(conn, 200)

      assert body["type"] == "EntityTypeInfo"
      assert body["typeName"] == "Sensor"
      assert body["entityCount"] >= 1
      assert is_list(body["attributeDetails"])
    end
  end
end
