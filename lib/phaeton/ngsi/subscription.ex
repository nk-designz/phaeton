defmodule Phaeton.NGSI.Subscription do
  @moduledoc """
  Manages NGSI-LD subscriptions.
  """

  import Ecto.Query
  alias Phaeton.Repo
  alias Phaeton.NGSI.Subscription.SubscriptionDoc

  def create_subscription(%{"type" => "Subscription"} = sub_data) do
    id = Map.get(sub_data, "id", generate_subscription_id())
    sub_data = Map.put(sub_data, "id", id)

    attrs = %{
      id: id,
      body: Jason.encode!(sub_data),
      status: "active"
    }

    case %SubscriptionDoc{} |> SubscriptionDoc.changeset(attrs) |> Repo.insert() do
      {:ok, _doc} -> {:ok, id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_subscription(_), do: {:error, :bad_request}

  def get_subscription(id) do
    case Repo.get(SubscriptionDoc, id) do
      nil -> {:error, :not_found}
      doc -> {:ok, Jason.decode!(doc.body)}
    end
  end

  def list_subscriptions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    subs =
      SubscriptionDoc
      |> limit(^limit)
      |> Repo.all()
      |> Enum.map(fn doc -> Jason.decode!(doc.body) end)

    {:ok, subs}
  end

  def update_subscription(id, updates) do
    case Repo.get(SubscriptionDoc, id) do
      nil ->
        {:error, :not_found}

      doc ->
        current = Jason.decode!(doc.body)
        updated = Map.merge(current, updates)

        doc
        |> SubscriptionDoc.changeset(%{body: Jason.encode!(updated)})
        |> Repo.update()
    end
  end

  def delete_subscription(id) do
    case Repo.get(SubscriptionDoc, id) do
      nil -> {:error, :not_found}
      doc -> Repo.delete(doc)
    end
  end

  defp generate_subscription_id do
    "urn:ngsi-ld:Subscription:" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
