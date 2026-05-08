defmodule Phaeton.Accounts.Group do
  use Ecto.Schema
  import Ecto.Changeset

  alias Phaeton.Accounts.{User, GroupMembership}

  schema "groups" do
    field :name, :string
    field :tenant, :string
    field :description, :string

    many_to_many :users, User, join_through: GroupMembership

    timestamps(type: :utc_datetime)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :tenant, :description])
    |> validate_required([:name, :tenant])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_length(:tenant, min: 1, max: 64)
    |> unique_constraint([:name, :tenant], message: "already exists in this tenant")
  end
end
