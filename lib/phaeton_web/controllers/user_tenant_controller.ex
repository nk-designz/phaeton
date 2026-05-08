defmodule PhaetonWeb.UserTenantController do
  use PhaetonWeb, :controller

  @doc """
  Stores the selected active tenant in the session and redirects back.
  Called by the topbar tenant dropdown form (POST /users/active-tenant).
  """
  def update(conn, %{"active_tenant" => tenant}) do
    referer = get_req_header(conn, "referer") |> List.first() || "/"
    path = URI.parse(referer).path || "/"
    cleaned = if tenant == "", do: nil, else: tenant

    conn
    |> put_session(:active_tenant, cleaned)
    |> redirect(to: path)
  end
end
