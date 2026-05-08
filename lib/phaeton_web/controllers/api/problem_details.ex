defmodule PhaetonWeb.API.ProblemDetails do
  @moduledoc """
  RFC 7807 / NGSI-LD ProblemDetails response helper.
  All error responses from NGSI-LD API endpoints should use this module.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @error_base "https://uri.etsi.org/ngsi-ld/errors/"

  @doc """
  Send an NGSI-LD ProblemDetails error response.
  """
  def send(conn, status, type, detail, opts \\ []) do
    instance = Keyword.get(opts, :instance)

    body = %{
      "type" => @error_base <> type,
      "title" => type,
      "status" => status,
      "detail" => detail
    }

    body = if instance, do: Map.put(body, "instance", instance), else: body

    conn
    |> put_status(status)
    |> put_resp_header("content-type", "application/problem+json")
    |> json(body)
  end

  # Common error types as convenience functions
  def bad_request(conn, detail), do: send(conn, 400, "BadRequestData", detail)
  def not_found(conn, detail), do: send(conn, 404, "ResourceNotFound", detail)
  def already_exists(conn, detail), do: send(conn, 409, "AlreadyExists", detail)
  def method_not_allowed(conn, detail), do: send(conn, 405, "MethodNotAllowed", detail)
  def unsupported_media_type(conn, detail), do: send(conn, 415, "UnsupportedMediaType", detail)
  def internal_error(conn, detail), do: send(conn, 500, "InternalError", detail)
  def too_complex(conn, detail), do: send(conn, 403, "TooComplexQuery", detail)
  def not_implemented(conn, detail), do: send(conn, 501, "OperationNotSupported", detail)
end
