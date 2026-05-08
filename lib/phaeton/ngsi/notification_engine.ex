defmodule Phaeton.NGSI.NotificationEngine do
  @moduledoc """
  Watches entity changes and delivers notifications to matching subscriptions.
  Uses PubSub to receive entity change events and Req to deliver HTTP notifications.
  """

  use GenServer

  alias Phaeton.NGSI.Subscription

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Notify the engine that an entity has been created or updated.
  """
  def entity_changed(entity_id, entity_data, change_type \\ :update) do
    Phoenix.PubSub.broadcast(
      Phaeton.PubSub,
      "ngsi:entity_changes",
      {:entity_changed, entity_id, entity_data, change_type}
    )
  end

  @doc """
  Notify the engine that an entity has been deleted.
  """
  def entity_deleted(entity_id) do
    Phoenix.PubSub.broadcast(
      Phaeton.PubSub,
      "ngsi:entity_changes",
      {:entity_deleted, entity_id}
    )
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Phaeton.PubSub, "ngsi:entity_changes")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:entity_changed, entity_id, entity_data, change_type}, state) do
    if Application.get_env(:phaeton, :enable_notifications, true) do
      Task.start(fn ->
        deliver_notifications(entity_id, entity_data, change_type)
      end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:entity_deleted, entity_id}, state) do
    if Application.get_env(:phaeton, :enable_notifications, true) do
      Task.start(fn ->
        deliver_notifications(entity_id, %{"id" => entity_id}, :delete)
      end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp deliver_notifications(entity_id, entity_data, change_type) do
    case Subscription.list_subscriptions(limit: 1000) do
      {:ok, subscriptions} ->
        entity_type = Map.get(entity_data, "type")

        matching_subs =
          Enum.filter(subscriptions, fn sub ->
            matches_subscription?(sub, entity_id, entity_type)
          end)

        Enum.each(matching_subs, fn sub ->
          deliver_notification(sub, entity_id, entity_data, change_type)
        end)

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp matches_subscription?(sub, entity_id, entity_type) do
    entities = get_in(sub, ["entities"]) || []
    watched_attrs = get_in(sub, ["watchedAttributes"]) || []

    # If no entities filter, match all
    entity_match =
      if entities == [] do
        true
      else
        Enum.any?(entities, fn e ->
          type_match = Map.get(e, "type") == nil or Map.get(e, "type") == entity_type

          id_match =
            case Map.get(e, "id") do
              nil ->
                case Map.get(e, "idPattern") do
                  nil ->
                    true

                  pattern ->
                    case Regex.compile(pattern) do
                      {:ok, regex} -> Regex.match?(regex, entity_id)
                      _ -> false
                    end
                end

              id ->
                id == entity_id
            end

          type_match and id_match
        end)
      end

    # watchedAttributes filter (if empty, match all)
    _attr_match = watched_attrs == []

    entity_match
  end

  defp deliver_notification(sub, _entity_id, entity_data, _change_type) do
    notification = get_in(sub, ["notification"]) || %{}
    endpoint = get_in(notification, ["endpoint"]) || %{}
    uri = Map.get(endpoint, "uri")
    accept = Map.get(endpoint, "accept", "application/json")

    if uri do
      notification_body = %{
        "id" =>
          "urn:ngsi-ld:Notification:" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
        "type" => "Notification",
        "subscriptionId" => Map.get(sub, "id"),
        "notifiedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "data" => [entity_data]
      }

      headers = [{"content-type", accept}]

      # Add custom receiver info headers if present
      headers =
        case Map.get(endpoint, "receiverInfo") do
          nil ->
            headers

          receiver_info when is_list(receiver_info) ->
            Enum.reduce(receiver_info, headers, fn %{"key" => k, "value" => v}, acc ->
              [{k, v} | acc]
            end)

          _ ->
            headers
        end

      try do
        Req.post(uri, json: notification_body, headers: headers, receive_timeout: 10_000)
      rescue
        _ -> :error
      end
    end
  end
end
