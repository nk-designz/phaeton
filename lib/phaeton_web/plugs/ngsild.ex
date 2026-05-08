defmodule PhaetonWeb.Plugs.NGSILD do
  @moduledoc """
  Plug for NGSI-LD API request handling.
  Extracts @context from Link header and manages NGSILD-Tenant header.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> extract_context()
    |> extract_tenant()
  end

  defp extract_context(conn) do
    case get_req_header(conn, "link") do
      [link_header | _] ->
        case parse_link_context(link_header) do
          nil -> assign(conn, :ngsild_context, nil)
          context_url -> assign(conn, :ngsild_context, context_url)
        end

      [] ->
        assign(conn, :ngsild_context, nil)
    end
  end

  defp extract_tenant(conn) do
    case get_req_header(conn, "ngsild-tenant") do
      [tenant | _] -> assign(conn, :ngsild_tenant, tenant)
      [] -> assign(conn, :ngsild_tenant, nil)
    end
  end

  defp parse_link_context(header) do
    # Parse Link: <url>; rel="http://www.w3.org/ns/json-ld#context"
    parts = String.split(header, ";")

    with [url_part | rest] <- parts,
         url <-
           url_part |> String.trim() |> String.trim_leading("<") |> String.trim_trailing(">"),
         true <- Enum.any?(rest, &String.contains?(&1, "json-ld#context")) do
      url
    else
      _ -> nil
    end
  end
end
