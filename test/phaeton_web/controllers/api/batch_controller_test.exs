defmodule PhaetonWeb.API.BatchControllerTest do
  use PhaetonWeb.ConnCase

  defp unique_id(label) do
    hex = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "urn:ngsi-ld:Vehicle:#{label}_#{hex}"
  end

  defp make_entity(id) do
    %{
      "id" => id,
      "type" => "Vehicle",
      "speed" => %{"type" => "Property", "value" => 80}
    }
  end

  defp post_json_array(conn, path, list) do
    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(PhaetonWeb.Endpoint, :post, path, Jason.encode!(list))
  end

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("content-type", "application/json") |> put_api_token()}
  end

  describe "POST /ngsi-ld/v1/entityOperations/create" do
    test "batch creates multiple entities", %{conn: conn} do
      ids = for _ <- 1..3, do: unique_id("bcreate")
      entities = Enum.map(ids, &make_entity/1)

      conn = post_json_array(conn, "/ngsi-ld/v1/entityOperations/create", entities)
      body = json_response(conn, 201)

      assert is_list(body)
      assert length(body) == 3
    end

    test "returns 400 for non-array body", %{conn: conn} do
      conn = post(conn, "/ngsi-ld/v1/entityOperations/create", %{"id" => "bad"})
      assert json_response(conn, 400)["type"] =~ "BadRequestData"
    end

    test "returns 207 with partial failures", %{conn: conn} do
      id = unique_id("bdup")
      entity = make_entity(id)

      # Create one first, then try batch with same + new
      post(conn, "/ngsi-ld/v1/entities", entity)

      entities = [entity, make_entity(unique_id("bnew"))]
      conn = post_json_array(conn, "/ngsi-ld/v1/entityOperations/create", entities)
      body = json_response(conn, 207)

      assert is_list(body["errors"])
      assert length(body["errors"]) == 1
      assert length(body["success"]) == 1
    end
  end

  describe "POST /ngsi-ld/v1/entityOperations/upsert" do
    test "creates entities that don't exist and updates those that do", %{conn: conn} do
      id1 = unique_id("bupsert1")
      id2 = unique_id("bupsert2")

      # Pre-create one
      post(conn, "/ngsi-ld/v1/entities", make_entity(id1))

      entities = [
        %{"id" => id1, "type" => "Vehicle", "speed" => %{"type" => "Property", "value" => 150}},
        make_entity(id2)
      ]

      conn = post_json_array(conn, "/ngsi-ld/v1/entityOperations/upsert", entities)
      body = json_response(conn, 201)
      assert is_list(body)
      assert length(body) == 2
    end
  end

  describe "POST /ngsi-ld/v1/entityOperations/delete" do
    test "batch deletes entities", %{conn: conn} do
      ids = for _ <- 1..2, do: unique_id("bdel")

      Enum.each(ids, fn id ->
        post(conn, "/ngsi-ld/v1/entities", make_entity(id))
      end)

      conn = post_json_array(conn, "/ngsi-ld/v1/entityOperations/delete", ids)
      assert response(conn, 204)
    end

    test "returns 400 for non-array body", %{conn: conn} do
      conn = post(conn, "/ngsi-ld/v1/entityOperations/delete", %{"id" => "bad"})
      assert json_response(conn, 400)["type"] =~ "BadRequestData"
    end
  end

  describe "POST /ngsi-ld/v1/entityOperations/query" do
    test "queries entities via POST body", %{conn: conn} do
      id = unique_id("bquery")
      post(conn, "/ngsi-ld/v1/entities", make_entity(id))

      conn = post(conn, "/ngsi-ld/v1/entityOperations/query", %{"type" => "Vehicle"})
      body = json_response(conn, 200)
      assert is_list(body)
    end
  end
end
