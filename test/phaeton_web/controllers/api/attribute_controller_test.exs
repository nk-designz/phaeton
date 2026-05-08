defmodule PhaetonWeb.API.AttributeControllerTest do
  use PhaetonWeb.ConnCase

  defp unique_id(label) do
    hex = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "urn:ngsi-ld:Device:#{label}_#{hex}"
  end

  setup %{conn: conn} do
    conn = conn |> put_req_header("content-type", "application/json") |> put_api_token()

    id = unique_id("attrtest")

    entity = %{
      "id" => id,
      "type" => "Device",
      "status" => %{"type" => "Property", "value" => "active"}
    }

    post(conn, "/ngsi-ld/v1/entities", entity)

    {:ok, conn: conn}
  end

  describe "GET /ngsi-ld/v1/attributes" do
    test "returns AttributeList", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/attributes")
      body = json_response(conn, 200)

      assert body["type"] == "AttributeList"
      assert is_list(body["attributeList"])
    end
  end

  describe "GET /ngsi-ld/v1/attributes/:attr_id" do
    test "returns attribute info for an existing attribute", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/attributes/status")
      body = json_response(conn, 200)

      assert body["type"] == "Attribute"
      assert body["attributeName"] == "status"
      assert body["attributeCount"] >= 1
      assert is_list(body["attributeTypes"])
      assert is_list(body["typeNames"])
    end

    test "returns 404 for non-existent attribute", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/attributes/nonExistentAttr12345")
      assert json_response(conn, 404)["type"] =~ "ResourceNotFound"
    end
  end
end
