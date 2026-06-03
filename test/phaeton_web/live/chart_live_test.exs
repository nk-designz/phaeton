defmodule PhaetonWeb.ChartLiveTest do
  use PhaetonWeb.ConnCase

  import Phoenix.LiveViewTest
  import Phaeton.AccountsFixtures

  alias Phaeton.NGSI
  alias Phaeton.NGSI.Temporal

  test "state-valued attributes do not crash when selecting and filtering", %{conn: conn} do
    user = user_fixture()
    entity_id = "urn:ngsi-ld:Device:chart-state-#{System.unique_integer([:positive])}"

    entity = %{
      "id" => entity_id,
      "type" => "Device",
      "status" => %{
        "type" => "Property",
        "value" => "ok"
      }
    }

    assert {:ok, ^entity_id} = NGSI.create_entity(entity, user.tenant)

    assert {:ok, ^entity_id} =
             Temporal.upsert_temporal(%{
               "id" => entity_id,
               "type" => "Device",
               "status" => %{
                 "type" => "Property",
                 "value" => %{"mode" => "auto", "code" => 1},
                 "observedAt" => "2026-06-03T10:00:00Z"
               }
             })

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/charts")

    _ =
      view
      |> element("#entity-select-form")
      |> render_change(%{"entity_id" => entity_id})

    attr = "status"

    html =
      view
      |> element("#attr-select-form")
      |> render_change(%{"attr" => attr})

    assert html =~ "Raw Data"

    html =
      view
      |> element("#time-filter-form")
      |> render_submit(%{"timerel" => "after", "time_at" => "2026-06-03T09:00", "end_time_at" => ""})

    assert html =~ "Raw Data"
  end
end
