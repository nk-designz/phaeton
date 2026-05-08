defmodule PhaetonWeb.API.ContextControllerTest do
  use PhaetonWeb.ConnCase

  @valid_context %{
    "@context" => %{
      "Vehicle" => "https://uri.etsi.org/ngsi-ld/default-context/Vehicle",
      "speed" => "https://uri.etsi.org/ngsi-ld/default-context/speed"
    }
  }

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("content-type", "application/json") |> put_api_token()}
  end

  describe "POST /ngsi-ld/v1/jsonldContexts" do
    test "creates a context and returns 201", %{conn: conn} do
      conn = post(conn, "/ngsi-ld/v1/jsonldContexts", @valid_context)
      body = json_response(conn, 201)

      assert body["id"] =~ "urn:ngsi-ld:context:"
      [loc] = get_resp_header(conn, "location")
      assert loc =~ "jsonldContexts/"
    end
  end

  describe "GET /ngsi-ld/v1/jsonldContexts" do
    test "lists contexts", %{conn: conn} do
      post(conn, "/ngsi-ld/v1/jsonldContexts", @valid_context)

      conn = get(conn, "/ngsi-ld/v1/jsonldContexts")
      body = json_response(conn, 200)
      assert is_list(body)
    end

    test "lists contexts with details", %{conn: conn} do
      post(conn, "/ngsi-ld/v1/jsonldContexts", @valid_context)

      conn = get(conn, "/ngsi-ld/v1/jsonldContexts?details=true")
      body = json_response(conn, 200)
      assert is_list(body)

      if body != [] do
        first = List.first(body)
        assert Map.has_key?(first, "localId")
        assert Map.has_key?(first, "kind")
      end
    end
  end

  describe "GET /ngsi-ld/v1/jsonldContexts/:context_id" do
    test "retrieves a stored context", %{conn: conn} do
      create_conn = post(conn, "/ngsi-ld/v1/jsonldContexts", @valid_context)
      %{"id" => id} = json_response(create_conn, 201)

      conn = get(conn, "/ngsi-ld/v1/jsonldContexts/#{URI.encode(id)}")
      assert json_response(conn, 200)
    end

    test "returns 404 for non-existent context", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/jsonldContexts/#{URI.encode("urn:ngsi-ld:context:nope")}")
      assert json_response(conn, 404)["type"] =~ "ResourceNotFound"
    end
  end

  describe "DELETE /ngsi-ld/v1/jsonldContexts/:context_id" do
    test "deletes a context", %{conn: conn} do
      create_conn = post(conn, "/ngsi-ld/v1/jsonldContexts", @valid_context)
      %{"id" => id} = json_response(create_conn, 201)

      conn = delete(conn, "/ngsi-ld/v1/jsonldContexts/#{URI.encode(id)}")
      assert response(conn, 204)

      conn =
        build_conn() |> put_api_token() |> get("/ngsi-ld/v1/jsonldContexts/#{URI.encode(id)}")

      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent context", %{conn: conn} do
      conn = delete(conn, "/ngsi-ld/v1/jsonldContexts/#{URI.encode("urn:ngsi-ld:context:nope")}")
      assert json_response(conn, 404)
    end
  end
end
