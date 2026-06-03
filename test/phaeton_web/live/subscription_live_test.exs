defmodule PhaetonWeb.SubscriptionLiveTest do
  use PhaetonWeb.ConnCase

  import Phoenix.LiveViewTest
  import Phaeton.AccountsFixtures

  alias Phaeton.NGSI.Subscription

  defp subscription_fixture(attrs \\ %{}) do
    id = Map.get(attrs, "id", "urn:ngsi-ld:Subscription:test-#{System.unique_integer([:positive])}")

    sub =
      Map.merge(
        %{
          "id" => id,
          "type" => "Subscription",
          "entities" => [%{"type" => "Vehicle"}],
          "notification" => %{"endpoint" => %{"uri" => "http://example.com/notify"}}
        },
        Map.delete(attrs, "id")
      )

    {:ok, ^id} = Subscription.create_subscription(sub)
    id
  end

  test "redirects if user is not logged in", %{conn: conn} do
    assert {:error, redirect} = live(conn, ~p"/subscriptions")

    assert {:redirect, %{to: path, flash: flash}} = redirect
    assert path == ~p"/users/log-in"
    assert %{"error" => "You must log in to access this page."} = flash
  end

  test "deletes a subscription from the list", %{conn: conn} do
    user = user_fixture()
    id = subscription_fixture()

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/subscriptions")

    assert html =~ id

    lv
    |> element("button[phx-click='delete'][phx-value-id='#{id}']")
    |> render_click()

    refute render(lv) =~ id
    assert {:error, :not_found} = Subscription.get_subscription(id)
  end
end
