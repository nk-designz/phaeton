defmodule Phaeton.NGSI.Subscription.SubscriptionDoc do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "subscriptions" do
    field :body, :string
    field :status, :string, default: "active"

    timestamps(type: :utc_datetime)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:id, :body, :status])
    |> validate_required([:id, :body, :status])
    |> validate_inclusion(:status, ~w(active paused expired))
  end
end
