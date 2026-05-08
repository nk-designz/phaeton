defmodule PhaetonWeb.API.InfoControllerTest do
  use PhaetonWeb.ConnCase

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("content-type", "application/json") |> put_api_token()}
  end

  describe "GET /ngsi-ld/v1/info/sourceIdentity" do
    test "returns broker identity info", %{conn: conn} do
      conn = get(conn, "/ngsi-ld/v1/info/sourceIdentity")
      body = json_response(conn, 200)

      assert body["type"] == "ContextSourceIdentity"
      assert body["contextSourceType"] == "ContextBroker"
      assert body["supportedNGSILDVersion"] == "1.8"
      assert is_binary(body["id"])
      assert is_binary(body["contextSourceAlias"])
    end
  end
end
