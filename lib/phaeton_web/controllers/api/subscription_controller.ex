defmodule PhaetonWeb.API.SubscriptionController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI.Subscription

  # POST /ngsi-ld/v1/subscriptions
  def create(conn, params) do
    case Subscription.create_subscription(params) do
      {:ok, id} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/ngsi-ld/v1/subscriptions/#{URI.encode(id)}")
        |> json(%{"id" => id})

      {:error, :bad_request} ->
        problem_details(
          conn,
          400,
          "BadRequestData",
          "Invalid subscription data. 'type' must be 'Subscription'."
        )

      {:error, _changeset} ->
        problem_details(conn, 400, "BadRequestData", "Invalid subscription data.")
    end
  end

  # GET /ngsi-ld/v1/subscriptions
  def index(conn, params) do
    limit = Map.get(params, "limit", "100") |> parse_int(100)
    {:ok, subs} = Subscription.list_subscriptions(limit: limit)
    json(conn, subs)
  end

  # GET /ngsi-ld/v1/subscriptions/:subscription_id
  def show(conn, %{"subscription_id" => id}) do
    case Subscription.get_subscription(URI.decode(id)) do
      {:ok, sub} ->
        json(conn, sub)

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Subscription not found.")
    end
  end

  # PATCH /ngsi-ld/v1/subscriptions/:subscription_id
  def update(conn, %{"subscription_id" => id} = params) do
    updates = Map.drop(params, ["subscription_id"])

    case Subscription.update_subscription(URI.decode(id), updates) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Subscription not found.")
    end
  end

  # DELETE /ngsi-ld/v1/subscriptions/:subscription_id
  def delete(conn, %{"subscription_id" => id}) do
    case Subscription.delete_subscription(URI.decode(id)) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Subscription not found.")
    end
  end

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp problem_details(conn, status, type, detail) do
    conn
    |> put_status(status)
    |> json(%{
      "type" => "https://uri.etsi.org/ngsi-ld/errors/#{type}",
      "title" => type,
      "status" => status,
      "detail" => detail
    })
  end
end
