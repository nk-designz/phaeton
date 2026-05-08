defmodule PhaetonWeb.API.CSourceRegistrationControllerTest do
  use PhaetonWeb.ConnCase

  @valid_registration %{
    "type" => "ContextSourceRegistration",
    "information" => [
      %{
        "entities" => [%{"type" => "Vehicle"}],
        "propertyNames" => ["speed", "brandName"]
      }
    ],
    "endpoint" => "http://context-source.example.com/ngsi-ld/v1"
  }

  defp unique_reg_id do
    hex = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "urn:ngsi-ld:ContextSourceRegistration:test_#{hex}"
  end

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("content-type", "application/json") |> put_api_token()}
  end

  describe "POST /ngsi-ld/v1/csourceRegistrations" do
    test "creates a registration and returns 201", %{conn: conn} do
      id = unique_reg_id()
      reg = Map.put(@valid_registration, "id", id)

      conn = post(conn, "/ngsi-ld/v1/csourceRegistrations", reg)
      assert json_response(conn, 201)["id"] == id
      [loc] = get_resp_header(conn, "location")
      assert loc =~ "csourceRegistrations/"
    end

    test "returns 400 for wrong type", %{conn: conn} do
      bad = Map.put(@valid_registration, "type", "Invalid")
      conn = post(conn, "/ngsi-ld/v1/csourceRegistrations", bad)
      assert json_response(conn, 400)["type"] =~ "BadRequestData"
    end
  end

  describe "GET /ngsi-ld/v1/csourceRegistrations" do
    test "lists registrations", %{conn: conn} do
      id = unique_reg_id()
      reg = Map.put(@valid_registration, "id", id)
      post(conn, "/ngsi-ld/v1/csourceRegistrations", reg)

      conn = get(conn, "/ngsi-ld/v1/csourceRegistrations")
      body = json_response(conn, 200)
      assert is_list(body)
      assert Enum.any?(body, &(&1["id"] == id))
    end
  end

  describe "GET /ngsi-ld/v1/csourceRegistrations/:registration_id" do
    test "retrieves a registration", %{conn: conn} do
      id = unique_reg_id()
      reg = Map.put(@valid_registration, "id", id)
      post(conn, "/ngsi-ld/v1/csourceRegistrations", reg)

      conn = get(conn, "/ngsi-ld/v1/csourceRegistrations/#{URI.encode(id)}")
      body = json_response(conn, 200)
      assert body["id"] == id
      assert body["type"] == "ContextSourceRegistration"
    end

    test "returns 404 for non-existent registration", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/csourceRegistrations/#{URI.encode("urn:ngsi-ld:CSR:nope")}")
      assert json_response(conn, 404)["type"] =~ "ResourceNotFound"
    end
  end

  describe "PATCH /ngsi-ld/v1/csourceRegistrations/:registration_id" do
    test "updates a registration", %{conn: conn} do
      id = unique_reg_id()
      reg = Map.put(@valid_registration, "id", id)
      post(conn, "/ngsi-ld/v1/csourceRegistrations", reg)

      conn =
        patch(conn, "/ngsi-ld/v1/csourceRegistrations/#{URI.encode(id)}", %{
          "description" => "updated"
        })

      assert response(conn, 204)

      conn =
        build_conn()
        |> put_api_token()
        |> get("/ngsi-ld/v1/csourceRegistrations/#{URI.encode(id)}")

      body = json_response(conn, 200)
      assert body["description"] == "updated"
    end

    test "returns 404 for non-existent registration", %{conn: conn} do
      conn =
        patch(conn, "/ngsi-ld/v1/csourceRegistrations/#{URI.encode("urn:ngsi-ld:CSR:nope")}", %{
          "x" => "y"
        })

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /ngsi-ld/v1/csourceRegistrations/:registration_id" do
    test "deletes a registration", %{conn: conn} do
      id = unique_reg_id()
      reg = Map.put(@valid_registration, "id", id)
      post(conn, "/ngsi-ld/v1/csourceRegistrations", reg)

      conn = delete(conn, "/ngsi-ld/v1/csourceRegistrations/#{URI.encode(id)}")
      assert response(conn, 204)

      conn =
        build_conn()
        |> put_api_token()
        |> get("/ngsi-ld/v1/csourceRegistrations/#{URI.encode(id)}")

      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent registration", %{conn: conn} do
      conn =
        delete(conn, "/ngsi-ld/v1/csourceRegistrations/#{URI.encode("urn:ngsi-ld:CSR:nope")}")

      assert json_response(conn, 404)
    end
  end
end
