defmodule Phaeton.Store do
  @moduledoc """
  Triple store operations backed by SQLite3.
  Provides persistence for RDF triples and bridges between Ecto and RDF.ex.
  """

  import Ecto.Query
  alias Phaeton.Repo
  alias Phaeton.Store.Triple

  def insert_triple(attrs) do
    %Triple{}
    |> Triple.changeset(attrs)
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: [:subject, :predicate, :object_value, :graph_name]
    )
  end

  def insert_triples(triples_attrs) do
    Repo.transaction(fn ->
      Enum.each(triples_attrs, fn attrs ->
        case insert_triple(attrs) do
          {:ok, _triple} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  def insert_triples_no_tx(triples_attrs) do
    Enum.reduce_while(triples_attrs, :ok, fn attrs, :ok ->
      case insert_triple(attrs) do
        {:ok, _triple} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  def get_triples_by_subject(subject) do
    Triple
    |> where([t], t.subject == ^subject)
    |> Repo.all()
  end

  def get_triples_by_graph(graph_name) do
    Triple
    |> where([t], t.graph_name == ^graph_name)
    |> Repo.all()
  end

  def get_triples_by_subject_and_graph(subject, graph_name) do
    Triple
    |> where([t], t.subject == ^subject and t.graph_name == ^graph_name)
    |> Repo.all()
  end

  def delete_triples_by_graph(graph_name) do
    Triple
    |> where([t], t.graph_name == ^graph_name)
    |> Repo.delete_all()
  end

  def delete_triples_by_subject_and_graph(subject, graph_name) do
    Triple
    |> where([t], t.subject == ^subject and t.graph_name == ^graph_name)
    |> Repo.delete_all()
  end

  def delete_triple_by_predicate(subject, predicate, graph_name) do
    Triple
    |> where(
      [t],
      t.subject == ^subject and t.predicate == ^predicate and t.graph_name == ^graph_name
    )
    |> Repo.delete_all()
  end

  def list_distinct_subjects(graph_name \\ nil) do
    query =
      Triple
      |> select([t], t.subject)
      |> distinct(true)

    query =
      if graph_name do
        where(query, [t], t.graph_name == ^graph_name)
      else
        query
      end

    Repo.all(query)
  end

  def list_distinct_subjects_by_tenant(:all) do
    Triple
    |> select([t], t.subject)
    |> distinct(true)
    |> Repo.all()
  end

  def list_distinct_subjects_by_tenant(nil) do
    # Default tenant: only subjects where graph_name equals the subject itself (no prefix)
    Triple
    |> where([t], t.graph_name == t.subject)
    |> select([t], t.subject)
    |> distinct(true)
    |> Repo.all()
  end

  def list_distinct_subjects_by_tenant(tenant) do
    Triple
    |> where([t], fragment("? LIKE ?", t.graph_name, ^"#{tenant}:%"))
    |> select([t], t.subject)
    |> distinct(true)
    |> Repo.all()
  end

  def list_all_graph_name_subject_pairs do
    Triple
    |> select([t], {t.graph_name, t.subject})
    |> distinct(true)
    |> Repo.all()
  end

  def list_distinct_graphs do
    Triple
    |> select([t], t.graph_name)
    |> distinct(true)
    |> Repo.all()
  end

  def list_distinct_tenants do
    # Tenanted graph_names have the form "Tenant:entity_id".
    # Default-tenant graphs have graph_name == subject (no prefix).
    Triple
    |> where([t], t.graph_name != t.subject)
    |> select([t], t.graph_name)
    |> distinct(true)
    |> Repo.all()
    |> Enum.map(fn gname -> String.split(gname, ":", parts: 2) |> List.first() end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def find_graph_name_by_subject(subject) do
    Triple
    |> where([t], t.subject == ^subject)
    |> select([t], t.graph_name)
    |> limit(1)
    |> Repo.one()
  end

  def entity_exists?(graph_name) do
    Triple
    |> where([t], t.graph_name == ^graph_name)
    |> limit(1)
    |> Repo.exists?()
  end

  @doc """
  Convert an RDF.Graph to a list of triple attribute maps for persistence.
  """
  def graph_to_triple_attrs(%RDF.Graph{} = graph, graph_name \\ nil) do
    graph_name = graph_name || if graph.name, do: to_string(graph.name), else: "default"

    Enum.map(graph, fn {subject, predicate, object} ->
      {object_value, object_type, datatype, lang} = serialize_rdf_term(object)

      %{
        subject: to_string(subject),
        predicate: to_string(predicate),
        object_value: object_value,
        object_type: object_type,
        datatype: datatype,
        lang: lang,
        graph_name: graph_name
      }
    end)
  end

  @doc """
  Convert stored triples back into an RDF.Graph.
  """
  def triples_to_graph(triples, graph_name \\ nil) do
    rdf_triples =
      Enum.map(triples, fn triple ->
        subject = RDF.IRI.new!(triple.subject)
        predicate = RDF.IRI.new!(triple.predicate)

        object =
          deserialize_rdf_term(
            triple.object_value,
            triple.object_type,
            triple.datatype,
            triple.lang
          )

        {subject, predicate, object}
      end)

    name = if graph_name, do: RDF.IRI.new!(graph_name), else: nil
    RDF.Graph.new(init: rdf_triples, name: name)
  end

  defp serialize_rdf_term(%RDF.IRI{} = iri) do
    {to_string(iri), "iri", nil, nil}
  end

  defp serialize_rdf_term(%RDF.BlankNode{} = bnode) do
    {to_string(bnode), "blank_node", nil, nil}
  end

  defp serialize_rdf_term(%RDF.Literal{} = lit) do
    value = RDF.Literal.lexical(lit)
    datatype = to_string(RDF.Literal.datatype_id(lit))

    lang =
      case RDF.Literal.language(lit) do
        nil -> nil
        l -> to_string(l)
      end

    {value, "literal", datatype, lang}
  end

  defp deserialize_rdf_term(value, "iri", _datatype, _lang) do
    RDF.IRI.new!(value)
  end

  defp deserialize_rdf_term(value, "blank_node", _datatype, _lang) do
    # Strip the "_:" prefix if present
    id = String.replace_prefix(value, "_:", "")
    RDF.BlankNode.new(id)
  end

  defp deserialize_rdf_term(value, "literal", datatype, lang) do
    cond do
      lang && lang != "" ->
        RDF.LangString.new(value, language: lang)

      datatype ->
        RDF.Literal.new(value, datatype: RDF.IRI.new!(datatype))

      true ->
        RDF.XSD.String.new(value)
    end
  end
end
