defmodule Phaeton.NGSI.Context.ContextDoc do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "contexts" do
    field :body, :string
    field :kind, :string, default: "Hosted"
    field :url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(context, attrs) do
    context
    |> cast(attrs, [:id, :body, :kind, :url])
    |> validate_required([:id, :body, :kind])
    |> validate_inclusion(:kind, ~w(Cached Hosted ImplicitlyCreated))
  end
end
