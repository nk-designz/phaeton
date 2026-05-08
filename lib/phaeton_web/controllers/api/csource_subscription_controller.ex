defmodule PhaetonWeb.API.CSourceSubscriptionController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI.CSourceSubscription

  def create(conn, params) do
    case CSourceSubscription.create(params) do
      {:ok, id} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/ngsi-ld/v1/csourceSubscriptions/#{URI.encode(id)}")
        |> json(%{"id" => id})

      {:error, :bad_request} ->
        problem_details(
          conn,
          400,
          "BadRequestData",
          "Invalid subscription. 'type' must be 'Subscription'."
        )

      {:error, _changeset} ->
        problem_details(conn, 400, "BadRequestData", "Invalid subscription data.")
    end
  end

  def index(conn, params) do
    limit = parse_int(Map.get(params, "limit", "100"), 100)
    {:ok, subs} = CSourceSubscription.list(limit: limit)
    json(conn, subs)
  end

  def show(conn, %{"subscription_id" => id}) do
    case CSourceSubscription.get(URI.decode(id)) do
      {:ok, sub} ->
        json(conn, sub)

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Subscription not found.")
    end
  end

  def update(conn, %{"subscription_id" => id} = params) do
    updates = Map.drop(params, ["subscription_id"])

    case CSourceSubscription.update(URI.decode(id), updates) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Subscription not found.")
    end
  end

  def delete(conn, %{"subscription_id" => id}) do
    case CSourceSubscription.delete(URI.decode(id)) do
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
