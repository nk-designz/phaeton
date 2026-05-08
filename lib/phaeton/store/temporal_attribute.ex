defmodule Phaeton.Store.TemporalAttribute do
  use Ecto.Schema
  import Ecto.Changeset

  schema "temporal_attributes" do
    field :entity_id, :string
    field :attribute_name, :string
    field :instance_id, :string
    field :observed_at, :utc_datetime_usec
    field :attribute_type, :string, default: "Property"
    field :value, :string
    field :object_value, :string
    field :datatype, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(entity_id attribute_name instance_id observed_at attribute_type value)a
  @optional_fields ~w(object_value datatype)a

  def changeset(temporal, attrs) do
    temporal
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:instance_id)
  end
end
