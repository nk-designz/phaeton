defmodule PhaetonWeb.PageController do
  use PhaetonWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
