defmodule PhaetonWeb.API.EntityControllerTest do
  use PhaetonWeb.ConnCase

  @vehicle_entity %{
    "id" => "urn:ngsi-ld:Vehicle:Test001",
    "type" => "Vehicle",
    "brandName" => %{
      "type" => "Property",
      "value" => "Mercedes"
    },
    "speed" => %{
      "type" => "Property",
      "value" => 80,
      "observedAt" => "2017-07-29T12:00:04Z"
    },
    "isParked" => %{
      "type" => "Relationship",
      "object" => "urn:ngsi-ld:OffStreetParking:Downtown1"
    },
    "location" => %{
      "type" => "GeoProperty",
      "value" => %{
        "type" => "Point",
        "coordinates" => [-8.5, 41.2]
      }
    }
  }

  defp unique_id(label) do
    hex = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "urn:ngsi-ld:Vehicle:#{label}_#{hex}"
  end

  defp create_entity(conn, entity) do
    post(conn, "/ngsi-ld/v1/entities", entity)
  end

  defp entity_path(entity_id) do
    "/ngsi-ld/v1/entities/#{URI.encode(entity_id)}"
  end

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("content-type", "application/json") |> put_api_token()}
  end

  describe "POST /ngsi-ld/v1/entities" do
    test "creates an entity and returns 201 with location", %{conn: conn} do
      id = unique_id("create")
      entity = Map.put(@vehicle_entity, "id", id)
      conn = create_entity(conn, entity)

      assert response(conn, 201)
      [loc] = get_resp_header(conn, "location")
      assert loc =~ "entities/"
      assert json_response(conn, 201)["id"] == id
    end

    test "returns 409 for duplicate entity", %{conn: conn} do
      id = unique_id("dup")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)
      conn = create_entity(conn, entity)

      assert json_response(conn, 409)["type"] =~ "AlreadyExists"
    end

    test "returns 400 for missing id/type", %{conn: conn} do
      conn = post(conn, "/ngsi-ld/v1/entities", %{"name" => "test"})
      assert json_response(conn, 400)["type"] =~ "BadRequestData"
    end
  end

  describe "GET /ngsi-ld/v1/entities/:entity_id" do
    test "retrieves an existing entity with all attribute types", %{conn: conn} do
      id = unique_id("show")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)

      conn = get(conn, entity_path(id))
      body = json_response(conn, 200)

      assert body["id"] == id
      assert body["type"] == "Vehicle"
      assert body["brandName"]["type"] == "Property"
      assert body["brandName"]["value"] == "Mercedes"
      assert body["speed"]["value"] == 80
      assert body["speed"]["observedAt"] == "2017-07-29T12:00:04Z"
      assert body["isParked"]["type"] == "Relationship"
      assert body["isParked"]["object"] == "urn:ngsi-ld:OffStreetParking:Downtown1"
      assert body["location"]["type"] == "GeoProperty"
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn = get(conn, entity_path("urn:ngsi-ld:Vehicle:NoExist"))
      assert json_response(conn, 404)["type"] =~ "ResourceNotFound"
    end
  end

  describe "GET /ngsi-ld/v1/entities (query)" do
    test "queries entities by type", %{conn: conn} do
      id = unique_id("query_type")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)

      conn = get(conn, "/ngsi-ld/v1/entities?type=Vehicle")
      body = json_response(conn, 200)

      assert is_list(body)
      assert Enum.any?(body, &(&1["id"] == id))
    end

    test "queries with q filter on numeric value", %{conn: conn} do
      id = unique_id("qfilter")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)

      conn = get(conn, "/ngsi-ld/v1/entities?q=speed>50")
      body = json_response(conn, 200)
      assert is_list(body)
    end

    test "queries with attrs picker", %{conn: conn} do
      id = unique_id("attrs")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)

      conn = get(conn, "/ngsi-ld/v1/entities?type=Vehicle&attrs=speed")
      body = json_response(conn, 200)
      assert is_list(body)

      Enum.each(body, fn e ->
        assert Map.has_key?(e, "id")
        assert Map.has_key?(e, "type")
      end)
    end

    test "pagination with limit and count", %{conn: conn} do
      for i <- 1..3 do
        id = unique_id("page#{i}")
        e = Map.put(@vehicle_entity, "id", id)
        create_entity(conn, e)
      end

      conn = get(conn, "/ngsi-ld/v1/entities?type=Vehicle&limit=1&count=true")
      assert json_response(conn, 200)
      [count_str] = get_resp_header(conn, "ngsild-results-count")
      assert String.to_integer(count_str) >= 1
    end
  end

  describe "PATCH /ngsi-ld/v1/entities/:entity_id (merge)" do
    test "merges entity attributes and replaces values", %{conn: conn} do
      id = unique_id("merge")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)

      patch_data = %{"speed" => %{"type" => "Property", "value" => 120}}
      conn = patch(conn, entity_path(id), patch_data)
      assert response(conn, 204)

      conn = build_conn() |> put_api_token() |> get(entity_path(id))
      body = json_response(conn, 200)
      assert body["speed"]["value"] == 120
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn =
        patch(conn, entity_path("urn:ngsi-ld:Vehicle:NoExist"), %{
          "speed" => %{"type" => "Property", "value" => 10}
        })

      assert json_response(conn, 404)
    end
  end

  describe "PUT /ngsi-ld/v1/entities/:entity_id (replace)" do
    test "replaces an entity's attributes", %{conn: conn} do
      id = unique_id("replace")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)

      replacement = %{
        "type" => "Vehicle",
        "brandName" => %{"type" => "Property", "value" => "BMW"}
      }

      conn = put(conn, entity_path(id), replacement)
      assert response(conn, 204)

      conn = build_conn() |> put_api_token() |> get(entity_path(id))
      body = json_response(conn, 200)
      assert body["brandName"]["value"] == "BMW"
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn = put(conn, entity_path("urn:ngsi-ld:Vehicle:NoExist"), %{"type" => "Vehicle"})
      assert json_response(conn, 404)
    end
  end

  describe "DELETE /ngsi-ld/v1/entities/:entity_id" do
    test "deletes an existing entity", %{conn: conn} do
      id = unique_id("delete")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)

      conn = delete(conn, entity_path(id))
      assert response(conn, 204)

      conn = build_conn() |> put_api_token() |> get(entity_path(id))
      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn = delete(conn, entity_path("urn:ngsi-ld:Vehicle:NoExist"))
      assert json_response(conn, 404)
    end
  end

  describe "POST /ngsi-ld/v1/entities/:entity_id/attrs (append)" do
    test "appends new attributes", %{conn: conn} do
      id = unique_id("append")

      entity = %{
        "id" => id,
        "type" => "Vehicle",
        "speed" => %{"type" => "Property", "value" => 50}
      }

      create_entity(conn, entity)

      new_attrs = %{"color" => %{"type" => "Property", "value" => "red"}}
      conn = post(conn, entity_path(id) <> "/attrs", new_attrs)
      assert response(conn, 204)

      conn = build_conn() |> put_api_token() |> get(entity_path(id))
      body = json_response(conn, 200)
      assert body["color"]["value"] == "red"
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn =
        post(conn, entity_path("urn:ngsi-ld:Vehicle:NoExist") <> "/attrs", %{
          "x" => %{"type" => "Property", "value" => 1}
        })

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /ngsi-ld/v1/entities/:entity_id/attrs/:attr_id" do
    test "deletes an attribute from an entity", %{conn: conn} do
      id = unique_id("delattr")
      entity = Map.put(@vehicle_entity, "id", id)
      create_entity(conn, entity)

      conn = delete(conn, entity_path(id) <> "/attrs/brandName")
      assert response(conn, 204)
    end

    test "returns 404 for non-existent entity", %{conn: conn} do
      conn = delete(conn, entity_path("urn:ngsi-ld:Vehicle:NoExist") <> "/attrs/speed")
      assert json_response(conn, 404)
    end
  end
end
