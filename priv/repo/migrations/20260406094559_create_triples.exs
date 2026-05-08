defmodule Phaeton.Repo.Migrations.CreateTriples do
  use Ecto.Migration

  def change do
    create table(:triples) do
      add :subject, :string, null: false
      add :predicate, :string, null: false
      add :object_value, :text, null: false
      add :object_type, :string, null: false, default: "literal"
      add :datatype, :string
      add :lang, :string
      add :graph_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:triples, [:subject])
    create index(:triples, [:predicate])
    create index(:triples, [:graph_name])
    create index(:triples, [:subject, :predicate])
    create index(:triples, [:object_value, :object_type])
    create unique_index(:triples, [:subject, :predicate, :object_value, :graph_name])

    create table(:contexts, primary_key: false) do
      add :id, :string, primary_key: true
      add :body, :text, null: false
      add :kind, :string, null: false, default: "Hosted"
      add :url, :string

      timestamps(type: :utc_datetime)
    end

    create table(:subscriptions, primary_key: false) do
      add :id, :string, primary_key: true
      add :body, :text, null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end
  end
end
