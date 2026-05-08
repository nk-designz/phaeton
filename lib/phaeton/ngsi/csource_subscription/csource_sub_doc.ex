defmodule Phaeton.NGSI.CSourceSubscription.CSourceSubDoc do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "csource_subscriptions" do
    field :body, :string
    field :status, :string, default: "active"

    timestamps(type: :utc_datetime)
  end

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [:id, :body, :status])
    |> validate_required([:id, :body])
  end
end
