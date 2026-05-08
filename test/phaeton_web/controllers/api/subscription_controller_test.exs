defmodule PhaetonWeb.API.SubscriptionControllerTest do
  use PhaetonWeb.ConnCase

  @valid_subscription %{
    "type" => "Subscription",
    "entities" => [%{"type" => "Vehicle"}],
    "notification" => %{
      "endpoint" => %{
        "uri" => "http://localhost:9999/notify",
        "accept" => "application/json"
      }
    }
  }

  defp unique_sub_id do
    hex = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "urn:ngsi-ld:Subscription:test_#{hex}"
  end

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("content-type", "application/json") |> put_api_token()}
  end

  describe "POST /ngsi-ld/v1/subscriptions" do
    test "creates a subscription and returns 201 with location", %{conn: conn} do
      id = unique_sub_id()
      sub = Map.put(@valid_subscription, "id", id)

      conn = post(conn, "/ngsi-ld/v1/subscriptions", sub)
      assert json_response(conn, 201)["id"] == id
      [loc] = get_resp_header(conn, "location")
      assert loc =~ "subscriptions/"
    end

    test "auto-generates id when not provided", %{conn: conn} do
      conn = post(conn, "/ngsi-ld/v1/subscriptions", @valid_subscription)
      body = json_response(conn, 201)
      assert body["id"] =~ "urn:ngsi-ld:Subscription:"
    end

    test "returns 400 when type is not Subscription", %{conn: conn} do
      bad_sub = Map.put(@valid_subscription, "type", "Invalid")
      conn = post(conn, "/ngsi-ld/v1/subscriptions", bad_sub)
      assert json_response(conn, 400)["type"] =~ "BadRequestData"
    end
  end

  describe "GET /ngsi-ld/v1/subscriptions" do
    test "lists subscriptions", %{conn: conn} do
      id = unique_sub_id()
      sub = Map.put(@valid_subscription, "id", id)
      post(conn, "/ngsi-ld/v1/subscriptions", sub)

      conn = get(conn, "/ngsi-ld/v1/subscriptions")
      body = json_response(conn, 200)
      assert is_list(body)
      assert Enum.any?(body, &(&1["id"] == id))
    end
  end

  describe "GET /ngsi-ld/v1/subscriptions/:subscription_id" do
    test "retrieves a subscription by id", %{conn: conn} do
      id = unique_sub_id()
      sub = Map.put(@valid_subscription, "id", id)
      post(conn, "/ngsi-ld/v1/subscriptions", sub)

      conn = get(conn, "/ngsi-ld/v1/subscriptions/#{URI.encode(id)}")
      body = json_response(conn, 200)
      assert body["id"] == id
      assert body["type"] == "Subscription"
    end

    test "returns 404 for non-existent subscription", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/subscriptions/#{URI.encode("urn:ngsi-ld:Subscription:nope")}")
      assert json_response(conn, 404)["type"] =~ "ResourceNotFound"
    end
  end

  describe "PATCH /ngsi-ld/v1/subscriptions/:subscription_id" do
    test "updates a subscription", %{conn: conn} do
      id = unique_sub_id()
      sub = Map.put(@valid_subscription, "id", id)
      post(conn, "/ngsi-ld/v1/subscriptions", sub)

      conn =
        patch(conn, "/ngsi-ld/v1/subscriptions/#{URI.encode(id)}", %{"description" => "updated"})

      assert response(conn, 204)

      conn = build_conn() |> put_api_token() |> get("/ngsi-ld/v1/subscriptions/#{URI.encode(id)}")
      body = json_response(conn, 200)
      assert body["description"] == "updated"
    end

    test "returns 404 for non-existent subscription", %{conn: conn} do
      conn =
        patch(conn, "/ngsi-ld/v1/subscriptions/#{URI.encode("urn:ngsi-ld:Subscription:nope")}", %{
          "x" => "y"
        })

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /ngsi-ld/v1/subscriptions/:subscription_id" do
    test "deletes a subscription", %{conn: conn} do
      id = unique_sub_id()
      sub = Map.put(@valid_subscription, "id", id)
      post(conn, "/ngsi-ld/v1/subscriptions", sub)

      conn = delete(conn, "/ngsi-ld/v1/subscriptions/#{URI.encode(id)}")
      assert response(conn, 204)

      conn = build_conn() |> put_api_token() |> get("/ngsi-ld/v1/subscriptions/#{URI.encode(id)}")
      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent subscription", %{conn: conn} do
      conn =
        delete(conn, "/ngsi-ld/v1/subscriptions/#{URI.encode("urn:ngsi-ld:Subscription:nope")}")

      assert json_response(conn, 404)
    end
  end
end
