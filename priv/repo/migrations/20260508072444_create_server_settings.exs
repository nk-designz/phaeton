defmodule Phaeton.Repo.Migrations.CreateServerSettings do
  use Ecto.Migration

  def change do
    create table(:server_settings) do
      add :key, :string, null: false
      add :value, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:server_settings, [:key])

    # Seed the default value for registration_enabled
    execute(
      """
      INSERT INTO server_settings (key, value, inserted_at, updated_at)
      VALUES ('registration_enabled', 'true', datetime('now'), datetime('now'))
      """,
      "DELETE FROM server_settings WHERE key = 'registration_enabled'"
    )
  end
end
