defmodule PhaetonWeb.UserLive.Confirmation do
  use PhaetonWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: ~p"/users/log-in")}
  end

  @impl true
  def render(assigns), do: ~H""
end
