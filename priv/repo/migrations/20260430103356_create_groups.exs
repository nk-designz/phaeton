defmodule Phaeton.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :name, :string, null: false
      add :tenant, :string, null: false
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:groups, [:name, :tenant])
  end
end
