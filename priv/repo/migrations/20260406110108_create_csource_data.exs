defmodule Phaeton.Repo.Migrations.CreateCsourceData do
  use Ecto.Migration

  def change do
    create table(:csource_registrations, primary_key: false) do
      add :id, :string, primary_key: true
      add :body, :text, null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create table(:csource_subscriptions, primary_key: false) do
      add :id, :string, primary_key: true
      add :body, :text, null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end
  end
end
