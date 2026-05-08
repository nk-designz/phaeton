defmodule PhaetonWeb.Plugs.CheckSetup do
  @moduledoc """
  Redirects to /setup when the app has not been initialised yet (no users exist).
  Bypassed for the /setup path itself and internal dev routes.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: path} = conn, _opts) do
    if setup_path?(path) or not Phaeton.Accounts.needs_setup?() do
      conn
    else
      conn
      |> redirect(to: "/setup")
      |> halt()
    end
  end

  defp setup_path?(path) do
    String.starts_with?(path, "/setup") or
      String.starts_with?(path, "/dev/") or
      String.starts_with?(path, "/assets/") or
      String.starts_with?(path, "/phoenix/")
  end
end
