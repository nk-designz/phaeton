defmodule PhaetonWeb.API.CSourceRegistrationController do
  use PhaetonWeb, :controller

  alias Phaeton.NGSI.CSourceRegistration

  def create(conn, params) do
    case CSourceRegistration.create(params) do
      {:ok, id} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/ngsi-ld/v1/csourceRegistrations/#{URI.encode(id)}")
        |> json(%{"id" => id})

      {:error, :bad_request} ->
        problem_details(
          conn,
          400,
          "BadRequestData",
          "Invalid registration. 'type' must be 'ContextSourceRegistration'."
        )

      {:error, _changeset} ->
        problem_details(conn, 400, "BadRequestData", "Invalid registration data.")
    end
  end

  def index(conn, params) do
    limit = parse_int(Map.get(params, "limit", "100"), 100)
    {:ok, regs} = CSourceRegistration.list(limit: limit)
    json(conn, regs)
  end

  def show(conn, %{"registration_id" => id}) do
    case CSourceRegistration.get(URI.decode(id)) do
      {:ok, reg} ->
        json(conn, reg)

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Registration not found.")
    end
  end

  def update(conn, %{"registration_id" => id} = params) do
    updates = Map.drop(params, ["registration_id"])

    case CSourceRegistration.update(URI.decode(id), updates) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Registration not found.")
    end
  end

  def delete(conn, %{"registration_id" => id}) do
    case CSourceRegistration.delete(URI.decode(id)) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        problem_details(conn, 404, "ResourceNotFound", "Registration not found.")
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
