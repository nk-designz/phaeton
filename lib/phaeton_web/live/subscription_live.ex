defmodule PhaetonWeb.SubscriptionLive do
  use PhaetonWeb, :live_view

  alias Phaeton.NGSI.Subscription

  @impl true
  def mount(_params, _session, socket) do
    {:ok, subs} = Subscription.list_subscriptions()

    socket =
      socket
      |> assign(:page_title, "Subscriptions")
      |> stream(:subscriptions, subs,
        dom_id: fn sub ->
          "sub-" <> String.replace(sub["id"], ~r/[^a-zA-Z0-9]/, "-")
        end
      )
      |> assign(:sub_count, length(subs))

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Subscription.delete_subscription(id) do
      {:ok, _} ->
        {:ok, subs} = Subscription.list_subscriptions()

        {:noreply,
         socket
         |> put_flash(:info, "Subscription deleted")
         |> stream(:subscriptions, subs, reset: true)
         |> assign(:sub_count, length(subs))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete subscription")}
    end
  end

  defp short_id(id), do: id |> String.split(":") |> List.last()

  defp extract_entities(sub) do
    case get_in(sub, ["entities"]) do
      nil -> []
      entities -> entities
    end
  end

  defp extract_endpoint(sub) do
    case get_in(sub, ["notification", "endpoint", "uri"]) do
      nil -> get_in(sub, ["notification", "endpoint"]) || "—"
      uri -> uri
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:subscriptions} current_scope={@current_scope}>
      <div class="space-y-4">
        <%!-- Header --%>
        <div>
          <h1 class="text-2xl font-bold tracking-tight heading-gradient">Subscriptions</h1>
          <p class="text-sm opacity-50 mt-0.5">{@sub_count} active subscriptions</p>
        </div>

        <%!-- Subscription Cards --%>
        <div id="subscriptions-list" phx-update="stream" class="space-y-3">
          <div class="hidden only:flex flex-col items-center py-12 opacity-40">
            <.icon name="hero-bell-slash" class="size-12 mb-3 opacity-30" />
            <p class="text-sm">No subscriptions yet</p>
            <p class="text-xs mt-1">Create subscriptions via the NGSI-LD API</p>
          </div>
          <div
            :for={{dom_id, sub} <- @streams.subscriptions}
            id={dom_id}
            class="card bg-base-200/50 border border-base-300/50 rounded-xl p-5 hover:border-primary/20 transition-all group"
          >
            <div class="flex flex-col sm:flex-row sm:items-start gap-3">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1.5">
                  <.icon name="hero-bell" class="size-4 text-primary" />
                  <span class="font-semibold text-sm">{short_id(sub["id"])}</span>
                  <span class="badge badge-xs badge-success">active</span>
                </div>
                <div class="font-mono text-xs opacity-50 break-all mb-2">{sub["id"]}</div>

                <%!-- Watched entities --%>
                <div class="flex flex-wrap gap-2 mb-2">
                  <%= for entity_spec <- extract_entities(sub) do %>
                    <%= if entity_spec["type"] do %>
                      <span class="badge badge-sm badge-outline">
                        <.icon name="hero-tag" class="size-3 mr-1" />
                        {entity_spec["type"]}
                      </span>
                    <% end %>
                    <%= if entity_spec["idPattern"] do %>
                      <span class="badge badge-sm badge-ghost">
                        pattern: {entity_spec["idPattern"]}
                      </span>
                    <% end %>
                  <% end %>
                </div>

                <%!-- Notification endpoint --%>
                <div class="flex items-center gap-1.5 text-xs opacity-50">
                  <.icon name="hero-arrow-top-right-on-square" class="size-3" />
                  <span class="truncate">{extract_endpoint(sub)}</span>
                </div>

                <%!-- Watched attributes --%>
                <%= if sub["watchedAttributes"] do %>
                  <div class="flex flex-wrap gap-1.5 mt-2">
                    <%= for attr <- sub["watchedAttributes"] do %>
                      <span class="badge badge-xs badge-ghost">{attr}</span>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  phx-click="delete"
                  phx-value-id={sub["id"]}
                  data-confirm="Delete this subscription?"
                  class="btn btn-xs btn-ghost text-error"
                  title="Delete"
                >
                  <.icon name="hero-trash" class="size-3.5" />
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- API hint --%>
        <div class="card bg-base-200/30 border border-base-300/30 rounded-xl p-4">
          <div class="flex items-start gap-3">
            <.icon name="hero-information-circle" class="size-5 text-info opacity-60 mt-0.5" />
            <div class="text-xs opacity-50">
              <p class="font-medium mb-1">Create subscriptions via the API</p>
              <code class="bg-base-300/50 px-1.5 py-0.5 rounded text-[11px]">
                POST /ngsi-ld/v1/subscriptions
              </code>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
