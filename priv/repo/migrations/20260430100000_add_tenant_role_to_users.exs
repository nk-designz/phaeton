defmodule Phaeton.Repo.Migrations.AddTenantRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :tenant, :string, default: "default", null: false
      add :role, :string, default: "data_consumer", null: false
    end
  end
end
