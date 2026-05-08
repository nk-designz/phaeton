defmodule PhaetonWeb.API.CSourceSubscriptionControllerTest do
  use PhaetonWeb.ConnCase

  @valid_subscription %{
    "type" => "Subscription",
    "entities" => [%{"type" => "Vehicle"}],
    "notification" => %{
      "endpoint" => %{
        "uri" => "http://localhost:9999/cs-notify",
        "accept" => "application/json"
      }
    }
  }

  defp unique_id do
    hex = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "urn:ngsi-ld:CSourceSubscription:test_#{hex}"
  end

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("content-type", "application/json") |> put_api_token()}
  end

  describe "POST /ngsi-ld/v1/csourceSubscriptions" do
    test "creates a csource subscription", %{conn: conn} do
      id = unique_id()
      sub = Map.put(@valid_subscription, "id", id)

      conn = post(conn, "/ngsi-ld/v1/csourceSubscriptions", sub)
      assert json_response(conn, 201)["id"] == id
      [loc] = get_resp_header(conn, "location")
      assert loc =~ "csourceSubscriptions/"
    end

    test "returns 400 for wrong type", %{conn: conn} do
      bad = Map.put(@valid_subscription, "type", "Invalid")
      conn = post(conn, "/ngsi-ld/v1/csourceSubscriptions", bad)
      assert json_response(conn, 400)["type"] =~ "BadRequestData"
    end
  end

  describe "GET /ngsi-ld/v1/csourceSubscriptions" do
    test "lists csource subscriptions", %{conn: conn} do
      id = unique_id()
      sub = Map.put(@valid_subscription, "id", id)
      post(conn, "/ngsi-ld/v1/csourceSubscriptions", sub)

      conn = get(conn, "/ngsi-ld/v1/csourceSubscriptions")
      body = json_response(conn, 200)
      assert is_list(body)
      assert Enum.any?(body, &(&1["id"] == id))
    end
  end

  describe "GET /ngsi-ld/v1/csourceSubscriptions/:subscription_id" do
    test "retrieves a csource subscription", %{conn: conn} do
      id = unique_id()
      sub = Map.put(@valid_subscription, "id", id)
      post(conn, "/ngsi-ld/v1/csourceSubscriptions", sub)

      conn = get(conn, "/ngsi-ld/v1/csourceSubscriptions/#{URI.encode(id)}")
      body = json_response(conn, 200)
      assert body["id"] == id
    end

    test "returns 404 for non-existent", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/csourceSubscriptions/#{URI.encode("urn:ngsi-ld:CSSub:nope")}")
      assert json_response(conn, 404)
    end
  end

  describe "PATCH /ngsi-ld/v1/csourceSubscriptions/:subscription_id" do
    test "updates a csource subscription", %{conn: conn} do
      id = unique_id()
      sub = Map.put(@valid_subscription, "id", id)
      post(conn, "/ngsi-ld/v1/csourceSubscriptions", sub)

      conn =
        patch(conn, "/ngsi-ld/v1/csourceSubscriptions/#{URI.encode(id)}", %{
          "description" => "changed"
        })

      assert response(conn, 204)
    end

    test "returns 404 for non-existent", %{conn: conn} do
      conn =
        patch(conn, "/ngsi-ld/v1/csourceSubscriptions/#{URI.encode("urn:ngsi-ld:CSSub:nope")}", %{
          "x" => "y"
        })

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /ngsi-ld/v1/csourceSubscriptions/:subscription_id" do
    test "deletes a csource subscription", %{conn: conn} do
      id = unique_id()
      sub = Map.put(@valid_subscription, "id", id)
      post(conn, "/ngsi-ld/v1/csourceSubscriptions", sub)

      conn = delete(conn, "/ngsi-ld/v1/csourceSubscriptions/#{URI.encode(id)}")
      assert response(conn, 204)

      conn =
        build_conn()
        |> put_api_token()
        |> get("/ngsi-ld/v1/csourceSubscriptions/#{URI.encode(id)}")

      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent", %{conn: conn} do
      conn =
        delete(conn, "/ngsi-ld/v1/csourceSubscriptions/#{URI.encode("urn:ngsi-ld:CSSub:nope")}")

      assert json_response(conn, 404)
    end
  end
end
