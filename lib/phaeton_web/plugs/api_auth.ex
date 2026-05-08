defmodule PhaetonWeb.Plugs.APIAuth do
  @moduledoc """
  Authenticates NGSI-LD REST API requests via Bearer token.

  Expects: Authorization: Bearer phtn_<token>

  On success: assigns :current_api_user on the conn.
  On failure: halts with a 401 NGSI-LD error response.
  """

  import Plug.Conn
  alias Phaeton.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case Accounts.get_user_by_api_token(token) do
          nil -> unauthorized(conn)
          user -> assign(conn, :current_api_user, user)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    body =
      Jason.encode!(%{
        "type" => "https://uri.etsi.org/ngsi-ld/errors/Unauthorized",
        "title" => "Unauthorized",
        "detail" =>
          "A valid Bearer token is required. Generate one via the admin panel under Users → Tokens."
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end
