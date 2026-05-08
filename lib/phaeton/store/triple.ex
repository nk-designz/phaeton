defmodule Phaeton.Store.Triple do
  use Ecto.Schema
  import Ecto.Changeset

  schema "triples" do
    field :subject, :string
    field :predicate, :string
    field :object_value, :string
    field :object_type, :string, default: "literal"
    field :datatype, :string
    field :lang, :string
    field :graph_name, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(subject predicate object_value object_type graph_name)a
  @optional_fields ~w(datatype lang)a

  def changeset(triple, attrs) do
    triple
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:object_type, ~w(iri literal blank_node))
  end
end
