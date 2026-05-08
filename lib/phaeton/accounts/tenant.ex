defmodule Phaeton.Accounts.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tenants" do
    field :name, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-]+$/,
      message: "only letters, numbers, hyphens and underscores"
    )
    |> unique_constraint(:name)
  end
end
