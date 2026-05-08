defmodule Phaeton.Repo.Migrations.CreateTemporalData do
  use Ecto.Migration

  def change do
    create table(:temporal_attributes) do
      add :entity_id, :string, null: false
      add :attribute_name, :string, null: false
      add :instance_id, :string, null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :attribute_type, :string, null: false, default: "Property"
      add :value, :text, null: false
      add :object_value, :string
      add :datatype, :string

      timestamps(type: :utc_datetime)
    end

    create index(:temporal_attributes, [:entity_id])
    create index(:temporal_attributes, [:entity_id, :attribute_name])
    create index(:temporal_attributes, [:observed_at])
    create unique_index(:temporal_attributes, [:instance_id])
  end
end
