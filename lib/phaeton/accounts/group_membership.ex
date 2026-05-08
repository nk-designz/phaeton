defmodule Phaeton.Accounts.GroupMembership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Phaeton.Accounts.{User, Group}

  schema "group_memberships" do
    belongs_to :user, User
    belongs_to :group, Group

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :group_id])
    |> validate_required([:user_id, :group_id])
    |> unique_constraint([:user_id, :group_id], message: "user is already a member of this group")
  end
end
