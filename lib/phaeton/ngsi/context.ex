defmodule Phaeton.NGSI.Context do
  @moduledoc """
  Manages JSON-LD @context documents for the NGSI-LD API.
  Handles storing, serving, and resolving @context references.
  """

  import Ecto.Query
  alias Phaeton.Repo
  alias Phaeton.NGSI.Context.ContextDoc

  @default_context "https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context-v1.8.jsonld"

  def default_context, do: @default_context

  def create_context(body, opts \\ []) do
    id = Keyword.get(opts, :id, generate_context_id())
    url = Keyword.get(opts, :url)
    kind = Keyword.get(opts, :kind, "Hosted")

    attrs = %{
      id: id,
      body: Jason.encode!(body),
      kind: kind,
      url: url
    }

    %ContextDoc{}
    |> ContextDoc.changeset(attrs)
    |> Repo.insert()
  end

  def get_context(id) do
    case Repo.get(ContextDoc, id) do
      nil -> {:error, :not_found}
      doc -> {:ok, Jason.decode!(doc.body)}
    end
  end

  def list_contexts(opts \\ []) do
    kind = Keyword.get(opts, :kind)
    details = Keyword.get(opts, :details, false)

    query = from(c in ContextDoc)

    query =
      if kind do
        where(query, [c], c.kind == ^kind)
      else
        query
      end

    contexts = Repo.all(query)

    if details do
      {:ok,
       Enum.map(contexts, fn c ->
         %{
           "URL" => c.url || c.id,
           "localId" => c.id,
           "kind" => c.kind,
           "timestamp" => DateTime.to_iso8601(c.inserted_at)
         }
       end)}
    else
      {:ok, Enum.map(contexts, fn c -> c.url || c.id end)}
    end
  end

  def delete_context(id) do
    case Repo.get(ContextDoc, id) do
      nil -> {:error, :not_found}
      doc -> Repo.delete(doc)
    end
  end

  @doc """
  Resolve a @context value from a request. Handles Link header and inline contexts.
  """
  def resolve_context(nil), do: @default_context

  def resolve_context(context) when is_binary(context), do: context

  def resolve_context(context) when is_list(context), do: context

  def resolve_context(context) when is_map(context), do: context

  @doc """
  Expand a short attribute name using context mappings.
  If the name already contains :// it's assumed to be a full IRI.
  """
  def expand_term(name, _context) when is_binary(name) do
    if String.contains?(name, "://") do
      name
    else
      "https://uri.etsi.org/ngsi-ld/" <> name
    end
  end

  @doc """
  Compact a full IRI to a short name using context mappings.
  """
  def compact_term(iri, _context) when is_binary(iri) do
    ngsild_base = "https://uri.etsi.org/ngsi-ld/"

    if String.starts_with?(iri, ngsild_base) do
      String.replace_prefix(iri, ngsild_base, "")
    else
      iri
    end
  end

  @doc """
  Add @context to an entity response based on content type and request context.
  """
  def add_context_to_entity(entity, context) when is_map(entity) do
    Map.put(entity, "@context", context || @default_context)
  end

  def add_context_to_entities(entities, context) when is_list(entities) do
    ctx = context || @default_context
    Enum.map(entities, &Map.put(&1, "@context", ctx))
  end

  defp generate_context_id do
    "urn:ngsi-ld:context:" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
