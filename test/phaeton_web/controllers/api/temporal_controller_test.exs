defmodule PhaetonWeb.API.TemporalControllerTest do
  use PhaetonWeb.ConnCase

  defp unique_id(label) do
    hex = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "urn:ngsi-ld:Vehicle:#{label}_#{hex}"
  end

  @temporal_entity %{
    "id" => "urn:ngsi-ld:Vehicle:TempTest",
    "type" => "Vehicle",
    "speed" => %{
      "type" => "Property",
      "value" => 80,
      "observedAt" => "2024-01-15T10:00:00Z"
    }
  }

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("content-type", "application/json") |> put_api_token()}
  end

  describe "POST /ngsi-ld/v1/temporal/entities" do
    test "creates a temporal entity", %{conn: conn} do
      id = unique_id("tcreate")
      entity = Map.put(@temporal_entity, "id", id)
      conn = post(conn, "/ngsi-ld/v1/temporal/entities", entity)

      assert json_response(conn, 201)["id"] == id
      [loc] = get_resp_header(conn, "location")
      assert loc =~ "temporal/entities/"
    end

    test "returns 400 for missing id", %{conn: conn} do
      conn = post(conn, "/ngsi-ld/v1/temporal/entities", %{"type" => "Vehicle"})
      assert json_response(conn, 400)["type"] =~ "BadRequestData"
    end
  end

  describe "GET /ngsi-ld/v1/temporal/entities" do
    test "queries temporal entities", %{conn: conn} do
      id = unique_id("tquery")
      entity = Map.put(@temporal_entity, "id", id)
      post(conn, "/ngsi-ld/v1/temporal/entities", entity)

      conn = get(conn, "/ngsi-ld/v1/temporal/entities")
      body = json_response(conn, 200)

      assert is_list(body)
    end

    test "queries with time filter", %{conn: conn} do
      id = unique_id("ttime")
      entity = Map.put(@temporal_entity, "id", id)
      post(conn, "/ngsi-ld/v1/temporal/entities", entity)

      conn = get(conn, "/ngsi-ld/v1/temporal/entities?timerel=after&timeAt=2023-01-01T00:00:00Z")
      body = json_response(conn, 200)
      assert is_list(body)
    end
  end

  describe "GET /ngsi-ld/v1/temporal/entities/:entity_id" do
    test "retrieves a temporal entity", %{conn: conn} do
      id = unique_id("tshow")
      entity = Map.put(@temporal_entity, "id", id)
      post(conn, "/ngsi-ld/v1/temporal/entities", entity)

      conn = get(conn, "/ngsi-ld/v1/temporal/entities/#{URI.encode(id)}")
      body = json_response(conn, 200)

      assert body["id"] == id
    end

    test "returns 404 for non-existent temporal entity", %{conn: conn} do
      conn =
        get(conn, "/ngsi-ld/v1/temporal/entities/#{URI.encode("urn:ngsi-ld:Vehicle:NoExist")}")

      assert json_response(conn, 404)["type"] =~ "ResourceNotFound"
    end
  end

  describe "DELETE /ngsi-ld/v1/temporal/entities/:entity_id" do
    test "deletes temporal entity data", %{conn: conn} do
      id = unique_id("tdel")
      entity = Map.put(@temporal_entity, "id", id)
      post(conn, "/ngsi-ld/v1/temporal/entities", entity)

      conn = delete(conn, "/ngsi-ld/v1/temporal/entities/#{URI.encode(id)}")
      assert response(conn, 204)

      conn =
        build_conn() |> put_api_token() |> get("/ngsi-ld/v1/temporal/entities/#{URI.encode(id)}")

      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent temporal entity", %{conn: conn} do
      conn =
        delete(conn, "/ngsi-ld/v1/temporal/entities/#{URI.encode("urn:ngsi-ld:Vehicle:NoExist")}")

      assert json_response(conn, 404)
    end
  end

  describe "POST /ngsi-ld/v1/temporal/entities/:entity_id/attrs" do
    test "appends temporal attributes", %{conn: conn} do
      id = unique_id("tappend")
      entity = Map.put(@temporal_entity, "id", id)
      post(conn, "/ngsi-ld/v1/temporal/entities", entity)

      new_attrs = %{
        "speed" => %{
          "type" => "Property",
          "value" => 100,
          "observedAt" => "2024-01-15T11:00:00Z"
        }
      }

      conn = post(conn, "/ngsi-ld/v1/temporal/entities/#{URI.encode(id)}/attrs", new_attrs)
      assert response(conn, 204)
    end
  end

  describe "POST /ngsi-ld/v1/temporal/entityOperations/query" do
    test "batch queries temporal entities", %{conn: conn} do
      id = unique_id("tbatch")
      entity = Map.put(@temporal_entity, "id", id)
      post(conn, "/ngsi-ld/v1/temporal/entities", entity)

      conn = post(conn, "/ngsi-ld/v1/temporal/entityOperations/query", %{"type" => "Vehicle"})
      body = json_response(conn, 200)
      assert is_list(body)
    end
  end
end
