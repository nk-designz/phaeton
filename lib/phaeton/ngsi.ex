defmodule Phaeton.NGSI do
  @moduledoc """
  Public API for NGSI-LD entity operations.
  Manages entity lifecycle through GenServer processes with RDF graph persistence.
  """

  alias Phaeton.Store
  alias Phaeton.NGSI.{Entity, EntityServer, EntitySupervisor, NotificationEngine, Temporal}

  @doc """
  Create a new NGSI-LD entity. Returns {:ok, entity_id} or {:error, reason}.
  """
  def create_entity(entity_data, tenant \\ nil)

  def create_entity(%{"id" => entity_id, "type" => _type} = entity_data, tenant) do
    gname = entity_graph_name(tenant, entity_id)

    if EntityServer.alive?(gname) or Store.entity_exists?(gname) do
      {:error, :already_exists}
    else
      graph = Entity.ngsi_to_graph(entity_data)

      with {:ok, _} <- Store.insert_triples(Store.graph_to_triple_attrs(graph, gname)),
           {:ok, _pid} <- EntitySupervisor.start_entity(entity_id, gname, graph) do
        NotificationEngine.entity_changed(entity_id, entity_data, :create)
        {:ok, entity_id}
      end
    end
  end

  def create_entity(_, _tenant), do: {:error, :bad_request}

  @doc """
  Retrieve an NGSI-LD entity by ID.
  """
  def get_entity(entity_id, tenant \\ nil) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      EntityServer.get_entity(gname)
    else
      {:error, :not_found}
    end
  end

  @doc """
  Query entities with optional filters. Pass `tenant: :all` to query across all tenants (UI admin view).
  """
  def query_entities(params \\ %{}, tenant \\ nil)

  def query_entities(params, :all) do
    type_filter = Map.get(params, "type")
    id_filter = Map.get(params, "id")
    id_pattern = Map.get(params, "idPattern")
    limit = parse_int(Map.get(params, "limit"), 100)
    offset = parse_int(Map.get(params, "offset"), 0)
    count = Map.get(params, "count") == "true" || Map.get(params, "options") == "count"
    attrs_filter = Map.get(params, "attrs")
    q_filter = Map.get(params, "q")
    scope_q = Map.get(params, "scopeQ")

    pairs = Store.list_all_graph_name_subject_pairs()

    filtered_pairs =
      pairs
      |> maybe_filter_pairs_by_id(id_filter)
      |> maybe_filter_pairs_by_pattern(id_pattern)

    all_entities =
      filtered_pairs
      |> Enum.map(fn {gname, subject} ->
        ensure_entity_loaded(subject, gname)

        case EntityServer.get_entity(gname) do
          {:ok, entity} -> entity
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> maybe_filter_by_type(type_filter)
      |> maybe_filter_by_q(q_filter)
      |> maybe_filter_by_scope(scope_q)

    total_count = length(all_entities)

    entities =
      all_entities
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> maybe_pick_attrs(attrs_filter)

    {:ok, entities, %{total_count: total_count, limit: limit, offset: offset, count: count}}
  end

  def query_entities(params, tenant) do
    type_filter = Map.get(params, "type")
    id_filter = Map.get(params, "id")
    id_pattern = Map.get(params, "idPattern")
    limit = parse_int(Map.get(params, "limit"), 100)
    offset = parse_int(Map.get(params, "offset"), 0)
    count = Map.get(params, "count") == "true" || Map.get(params, "options") == "count"
    attrs_filter = Map.get(params, "attrs")
    q_filter = Map.get(params, "q")
    scope_q = Map.get(params, "scopeQ")

    subjects = Store.list_distinct_subjects_by_tenant(tenant)

    filtered_subjects =
      subjects
      |> maybe_filter_by_id(id_filter)
      |> maybe_filter_by_pattern(id_pattern)

    all_entities =
      filtered_subjects
      |> Enum.map(fn subject ->
        gname = entity_graph_name(tenant, subject)
        ensure_entity_loaded(subject, gname)

        case EntityServer.get_entity(gname) do
          {:ok, entity} -> entity
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> maybe_filter_by_type(type_filter)
      |> maybe_filter_by_q(q_filter)
      |> maybe_filter_by_scope(scope_q)

    total_count = length(all_entities)

    entities =
      all_entities
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> maybe_pick_attrs(attrs_filter)

    {:ok, entities, %{total_count: total_count, limit: limit, offset: offset, count: count}}
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp maybe_pick_attrs(entities, nil), do: entities

  defp maybe_pick_attrs(entities, attrs_str) do
    attrs = String.split(attrs_str, ",") |> Enum.map(&String.trim/1)
    keep = attrs ++ ["id", "type", "createdAt", "modifiedAt", "scope"]

    Enum.map(entities, fn entity ->
      Map.take(entity, keep)
    end)
  end

  @doc """
  Delete an entity by ID.
  """
  def delete_entity(entity_id, tenant \\ nil) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      EntitySupervisor.stop_entity(gname)
      Store.delete_triples_by_subject_and_graph(entity_id, gname)
      NotificationEngine.entity_deleted(entity_id)
      :ok
    else
      if Store.entity_exists?(gname) do
        Store.delete_triples_by_subject_and_graph(entity_id, gname)
        NotificationEngine.entity_deleted(entity_id)
        :ok
      else
        {:error, :not_found}
      end
    end
  end

  @doc """
  Merge entity (PATCH /entities/{id}) - JSON Merge Patch semantics.
  """
  def merge_entity(entity_id, fragment, tenant \\ nil) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      attrs_graph = Entity.fragment_to_triples(entity_id, fragment)

      case EntityServer.merge_entity(gname, attrs_graph) do
        :ok ->
          notify_entity_update(entity_id, fragment, tenant)
          :ok

        error ->
          error
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Replace entity (PUT /entities/{id}).
  """
  def replace_entity(entity_id, entity_data, tenant \\ nil)

  def replace_entity(entity_id, %{"type" => _type} = entity_data, tenant) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      entity_data = Map.put(entity_data, "id", entity_id)
      new_graph = Entity.ngsi_to_graph(entity_data)

      case EntityServer.replace_graph(gname, new_graph) do
        :ok ->
          notify_entity_update(entity_id, nil, tenant)
          :ok

        error ->
          error
      end
    else
      {:error, :not_found}
    end
  end

  def replace_entity(_entity_id, _, _tenant), do: {:error, :bad_request}

  @doc """
  Append attributes to an entity.
  """
  def append_attrs(entity_id, attrs, opts \\ [], tenant \\ nil) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      attrs_graph = Entity.fragment_to_triples(entity_id, attrs)

      case EntityServer.append_attrs(gname, attrs_graph, opts) do
        :ok ->
          notify_entity_update(entity_id, attrs, tenant)
          :ok

        error ->
          error
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Update existing attributes of an entity.
  """
  def update_attrs(entity_id, attrs, tenant \\ nil) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      attrs_graph = Entity.fragment_to_triples(entity_id, attrs)

      case EntityServer.update_attrs(gname, attrs_graph) do
        :ok ->
          notify_entity_update(entity_id, attrs, tenant)
          :ok

        error ->
          error
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Delete an attribute from an entity.
  """
  def delete_attr(entity_id, attr_id, tenant \\ nil) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      attr_iri =
        if String.contains?(attr_id, "://") do
          attr_id
        else
          "https://uri.etsi.org/ngsi-ld/" <> attr_id
        end

      EntityServer.delete_attr(gname, attr_iri)
    else
      {:error, :not_found}
    end
  end

  @doc """
  Partial update of a specific attribute.
  """
  def update_attr(entity_id, attr_id, attr_fragment, tenant \\ nil) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      attrs = %{attr_id => attr_fragment}
      attrs_graph = Entity.fragment_to_triples(entity_id, attrs)

      case EntityServer.update_attrs(gname, attrs_graph) do
        :ok ->
          notify_entity_update(entity_id, attrs, tenant)
          :ok

        error ->
          error
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Replace a specific attribute.
  """
  def replace_attr(entity_id, attr_id, attr_fragment, tenant \\ nil) do
    gname = entity_graph_name(tenant, entity_id)
    ensure_entity_loaded(entity_id, gname)

    if EntityServer.alive?(gname) do
      # First delete old attribute, then add new
      attr_iri =
        if String.contains?(attr_id, "://") do
          attr_id
        else
          "https://uri.etsi.org/ngsi-ld/" <> attr_id
        end

      with :ok <- EntityServer.delete_attr(gname, attr_iri) do
        attrs = %{attr_id => attr_fragment}
        attrs_graph = Entity.fragment_to_triples(entity_id, attrs)

        case EntityServer.append_attrs(gname, attrs_graph) do
          :ok ->
            notify_entity_update(entity_id, %{attr_id => attr_fragment}, tenant)
            :ok

          error ->
            error
        end
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Get available entity types, optionally scoped to a tenant.
  """
  def get_types(tenant \\ :all) do
    rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

    import Ecto.Query

    types =
      Phaeton.Store.Triple
      |> where([t], t.predicate == ^rdf_type)
      |> tenant_graph_filter(tenant)
      |> select([t], t.object_value)
      |> distinct(true)
      |> Phaeton.Repo.all()
      |> Enum.map(&Entity.compact_iri/1)

    {:ok, types}
  end

  def get_type_info(type_name, tenant \\ :all) do
    rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    ngsild_base = "https://uri.etsi.org/ngsi-ld/"

    type_iri =
      if String.contains?(type_name, "://"), do: type_name, else: ngsild_base <> type_name

    import Ecto.Query

    # Get all subjects of this type
    subjects =
      Phaeton.Store.Triple
      |> where([t], t.predicate == ^rdf_type and t.object_value == ^type_iri)
      |> tenant_graph_filter(tenant)
      |> select([t], t.subject)
      |> Phaeton.Repo.all()

    entity_count = length(subjects)

    # Get all predicates used by these subjects, excluding system ones
    system_preds =
      MapSet.new([
        rdf_type,
        ngsild_base <> "createdAt",
        ngsild_base <> "modifiedAt",
        ngsild_base <> "deletedAt",
        ngsild_base <> "scope"
      ])

    attribute_details =
      if subjects != [] do
        Phaeton.Store.Triple
        |> where([t], t.subject in ^subjects)
        |> select([t], {t.predicate, t.object_value, t.object_type})
        |> Phaeton.Repo.all()
        |> Enum.reject(fn {pred, _, _} ->
          pred in system_preds or String.contains?(pred, "#")
        end)
        |> Enum.group_by(fn {pred, _, _} -> pred end)
        |> Enum.map(fn {pred, entries} ->
          # Determine attribute type from the #type meta-predicate
          type_pred = pred <> "#type"

          attr_type_iri =
            Phaeton.Store.Triple
            |> where([t], t.predicate == ^type_pred and t.subject in ^subjects)
            |> select([t], t.object_value)
            |> limit(1)
            |> Phaeton.Repo.one()

          attr_type =
            case attr_type_iri do
              nil -> "Property"
              iri -> Entity.compact_iri(iri)
            end

          %{
            "id" => Entity.compact_iri(pred),
            "type" => "Attribute",
            "attributeName" => Entity.compact_iri(pred),
            "attributeCount" => length(entries),
            "attributeTypes" => [attr_type]
          }
        end)
      else
        []
      end

    {:ok, %{entity_count: entity_count, attribute_details: attribute_details}}
  end

  def get_attributes do
    ngsild_base = "https://uri.etsi.org/ngsi-ld/"

    import Ecto.Query

    system_preds =
      [
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
        ngsild_base <> "createdAt",
        ngsild_base <> "modifiedAt",
        ngsild_base <> "deletedAt",
        ngsild_base <> "scope"
      ]

    attrs =
      Phaeton.Store.Triple
      |> where([t], t.predicate not in ^system_preds)
      |> where([t], fragment("? NOT LIKE '%#%'", t.predicate))
      |> select([t], t.predicate)
      |> distinct(true)
      |> Phaeton.Repo.all()
      |> Enum.map(&Entity.compact_iri/1)

    {:ok, attrs}
  end

  def get_attribute_info(attr_name) do
    ngsild_base = "https://uri.etsi.org/ngsi-ld/"

    attr_iri =
      if String.contains?(attr_name, "://"), do: attr_name, else: ngsild_base <> attr_name

    import Ecto.Query

    entries =
      Phaeton.Store.Triple
      |> where([t], t.predicate == ^attr_iri)
      |> Phaeton.Repo.all()

    if entries == [] do
      {:error, :not_found}
    else
      type_pred = attr_iri <> "#type"

      attr_types =
        Phaeton.Store.Triple
        |> where([t], t.predicate == ^type_pred)
        |> select([t], t.object_value)
        |> distinct(true)
        |> Phaeton.Repo.all()
        |> Enum.map(&Entity.compact_iri/1)

      entity_types =
        entries
        |> Enum.map(& &1.subject)
        |> Enum.uniq()
        |> then(fn subjects ->
          rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

          Phaeton.Store.Triple
          |> where([t], t.predicate == ^rdf_type and t.subject in ^subjects)
          |> select([t], t.object_value)
          |> distinct(true)
          |> Phaeton.Repo.all()
          |> Enum.map(&Entity.compact_iri/1)
        end)

      {:ok,
       %{
         attribute_count: length(entries),
         attribute_types: if(attr_types == [], do: ["Property"], else: attr_types),
         type_names: entity_types
       }}
    end
  end

  # Batch operations

  @doc """
  Batch create entities.
  """
  def batch_create(entities, tenant \\ nil) when is_list(entities) do
    results =
      Enum.map(entities, fn entity ->
        case create_entity(entity, tenant) do
          {:ok, id} -> {:ok, id}
          {:error, reason} -> {:error, Map.get(entity, "id", "unknown"), reason}
        end
      end)

    success = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(fn {:ok, id} -> id end)

    errors =
      Enum.filter(results, &match?({:error, _, _}, &1))
      |> Enum.map(fn {:error, id, reason} -> %{"entityId" => id, "error" => to_string(reason)} end)

    {:ok, %{"success" => success, "errors" => errors}}
  end

  @doc """
  Batch delete entities.
  """
  def batch_delete(entity_ids, tenant \\ nil) when is_list(entity_ids) do
    results =
      Enum.map(entity_ids, fn id ->
        case delete_entity(id, tenant) do
          :ok -> {:ok, id}
          {:error, reason} -> {:error, id, reason}
        end
      end)

    success = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(fn {:ok, id} -> id end)

    errors =
      Enum.filter(results, &match?({:error, _, _}, &1))
      |> Enum.map(fn {:error, id, reason} -> %{"entityId" => id, "error" => to_string(reason)} end)

    {:ok, %{"success" => success, "errors" => errors}}
  end

  @doc """
  Batch upsert entities.
  """
  def batch_upsert(entities, opts \\ [], tenant \\ nil) when is_list(entities) do
    results =
      Enum.map(entities, fn entity ->
        entity_id = Map.get(entity, "id")

        case create_entity(entity, tenant) do
          {:ok, id} ->
            {:ok, id}

          {:error, :already_exists} ->
            update_mode = Keyword.get(opts, :mode, :replace)

            result =
              if update_mode == :update do
                merge_entity(entity_id, Map.drop(entity, ["id", "type"]), tenant)
              else
                replace_entity(entity_id, entity, tenant)
              end

            case result do
              :ok -> {:ok, entity_id}
              {:error, reason} -> {:error, entity_id, reason}
            end

          {:error, reason} ->
            {:error, entity_id || "unknown", reason}
        end
      end)

    success = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(fn {:ok, id} -> id end)

    errors =
      Enum.filter(results, &match?({:error, _, _}, &1))
      |> Enum.map(fn {:error, id, reason} -> %{"entityId" => id, "error" => to_string(reason)} end)

    {:ok, %{"success" => success, "errors" => errors}}
  end

  @doc """
  Get broker statistics for the dashboard.
  """
  def list_tenants, do: Store.list_distinct_tenants()

  def get_stats(tenant \\ :all) do
    import Ecto.Query

    triple_count = Phaeton.Repo.aggregate(Store.Triple, :count)
    temporal_count = Phaeton.Repo.aggregate(Phaeton.Store.TemporalAttribute, :count)
    subjects = Store.list_distinct_subjects_by_tenant(tenant)
    entity_count = length(subjects)
    {:ok, types} = get_types(tenant)
    {:ok, subs} = Phaeton.NGSI.Subscription.list_subscriptions()

    rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

    type_counts =
      Store.Triple
      |> where([t], t.predicate == ^rdf_type)
      |> tenant_graph_filter(tenant)
      |> group_by([t], t.object_value)
      |> select([t], {t.object_value, count(t.id)})
      |> Phaeton.Repo.all()
      |> Enum.map(fn {type_iri, count} -> {Entity.compact_iri(type_iri), count} end)
      |> Enum.into(%{})

    %{
      entity_count: entity_count,
      type_count: length(types),
      types: types,
      type_counts: type_counts,
      subscription_count: length(subs),
      triple_count: triple_count,
      temporal_count: temporal_count
    }
  end

  @doc """
  Get entity-relationship graph data for visualization.
  Returns %{nodes: [...], edges: [...]}.
  """
  def get_relationship_graph(tenant \\ :all) do
    import Ecto.Query

    ngsild_base = "https://uri.etsi.org/ngsi-ld/"
    rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

    type_map =
      Store.Triple
      |> where([t], t.predicate == ^rdf_type)
      |> tenant_graph_filter(tenant)
      |> select([t], {t.subject, t.object_value})
      |> Phaeton.Repo.all()
      |> Map.new(fn {subj, type_iri} -> {subj, Entity.compact_iri(type_iri)} end)

    rel_type_iri = ngsild_base <> "Relationship"

    rel_preds =
      Store.Triple
      |> where([t], fragment("? LIKE '%#type'", t.predicate) and t.object_value == ^rel_type_iri)
      |> tenant_graph_filter(tenant)
      |> select([t], fragment("REPLACE(?, '#type', '')", t.predicate))
      |> distinct(true)
      |> Phaeton.Repo.all()

    edges =
      if rel_preds != [] do
        Store.Triple
        |> where([t], t.predicate in ^rel_preds and t.object_type == "iri")
        |> tenant_graph_filter(tenant)
        |> select([t], %{source: t.subject, target: t.object_value, label: t.predicate})
        |> Phaeton.Repo.all()
        |> Enum.map(fn e ->
          %{source: e.source, target: e.target, label: Entity.compact_iri(e.label)}
        end)
      else
        []
      end

    nodes =
      type_map
      |> Enum.map(fn {id, type} ->
        short = id |> String.split(":") |> List.last()
        %{id: id, type: type, label: short}
      end)

    %{nodes: nodes, edges: edges}
  end

  # Applies a tenant-scoped graph_name filter to an Ecto query on Store.Triple.
  # :all    → no filter (all tenants)
  # nil     → default tenant only (graph_name == subject)
  # binary  → named tenant (graph_name LIKE "tenant:%")
  defp tenant_graph_filter(query, :all), do: query

  defp tenant_graph_filter(query, nil) do
    import Ecto.Query
    where(query, [t], t.graph_name == t.subject)
  end

  defp tenant_graph_filter(query, tenant) when is_binary(tenant) do
    import Ecto.Query
    where(query, [t], fragment("? LIKE ?", t.graph_name, ^"#{tenant}:%"))
  end

  # Load entity from DB into GenServer if not already running
  # For full replacements (no changed_attrs), upserts all attributes.
  # For partial updates, only records the changed attributes temporally.
  defp notify_entity_update(entity_id, changed_attrs, tenant) do
    case get_entity(entity_id, tenant) do
      {:ok, entity_data} ->
        NotificationEngine.entity_changed(entity_id, entity_data, :update)

        if changed_attrs do
          Temporal.append_temporal_attrs(entity_id, changed_attrs)
        else
          Temporal.upsert_temporal(entity_data)
        end

      _ ->
        :ok
    end
  end

  # Load entity from DB into GenServer if not already running
  defp ensure_entity_loaded(entity_id, gname) do
    unless EntityServer.alive?(gname) do
      triples = Store.get_triples_by_subject_and_graph(entity_id, gname)

      if triples != [] do
        graph = Store.triples_to_graph(triples, entity_id)
        EntitySupervisor.start_entity(entity_id, gname, graph)
      end
    end
  end

  defp entity_graph_name(nil, entity_id), do: entity_id
  defp entity_graph_name(tenant, entity_id), do: "#{tenant}:#{entity_id}"

  defp maybe_filter_by_id(subjects, nil), do: subjects

  defp maybe_filter_by_id(subjects, id_filter) do
    ids = String.split(id_filter, ",")
    Enum.filter(subjects, &(&1 in ids))
  end

  defp maybe_filter_by_pattern(subjects, nil), do: subjects

  defp maybe_filter_by_pattern(subjects, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Enum.filter(subjects, &Regex.match?(regex, &1))
      _ -> subjects
    end
  end

  defp maybe_filter_pairs_by_id(pairs, nil), do: pairs

  defp maybe_filter_pairs_by_id(pairs, id_filter) do
    ids = String.split(id_filter, ",")
    Enum.filter(pairs, fn {_gname, subject} -> subject in ids end)
  end

  defp maybe_filter_pairs_by_pattern(pairs, nil), do: pairs

  defp maybe_filter_pairs_by_pattern(pairs, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Enum.filter(pairs, fn {_gname, subject} -> Regex.match?(regex, subject) end)
      _ -> pairs
    end
  end

  defp maybe_filter_by_type(entities, nil), do: entities

  defp maybe_filter_by_type(entities, type_filter) do
    types = String.split(type_filter, ",")
    Enum.filter(entities, fn entity -> Map.get(entity, "type") in types end)
  end

  # NGSI-LD simple query language (q parameter)
  # Supports: attr==value, attr!=value, attr>value, attr<value, attr>=value, attr<=value
  # Supports semicolon (AND) and pipe (OR) combinators
  defp maybe_filter_by_q(entities, nil), do: entities

  defp maybe_filter_by_q(entities, q) do
    # Split by ; (AND) first, then | (OR) within each clause
    and_clauses = String.split(q, ";")

    Enum.filter(entities, fn entity ->
      Enum.all?(and_clauses, fn clause ->
        or_parts = String.split(clause, "|")

        Enum.any?(or_parts, fn part ->
          evaluate_q_expression(entity, String.trim(part))
        end)
      end)
    end)
  end

  defp evaluate_q_expression(entity, expr) do
    cond do
      String.contains?(expr, "!=") ->
        [attr, val] = String.split(expr, "!=", parts: 2)
        entity_attr_value(entity, String.trim(attr)) != parse_q_value(String.trim(val))

      String.contains?(expr, ">=") ->
        [attr, val] = String.split(expr, ">=", parts: 2)

        compare_values(
          entity_attr_value(entity, String.trim(attr)),
          parse_q_value(String.trim(val))
        ) in [:gt, :eq]

      String.contains?(expr, "<=") ->
        [attr, val] = String.split(expr, "<=", parts: 2)

        compare_values(
          entity_attr_value(entity, String.trim(attr)),
          parse_q_value(String.trim(val))
        ) in [:lt, :eq]

      String.contains?(expr, "==") ->
        [attr, val] = String.split(expr, "==", parts: 2)
        entity_attr_value(entity, String.trim(attr)) == parse_q_value(String.trim(val))

      String.contains?(expr, ">") ->
        [attr, val] = String.split(expr, ">", parts: 2)

        compare_values(
          entity_attr_value(entity, String.trim(attr)),
          parse_q_value(String.trim(val))
        ) == :gt

      String.contains?(expr, "<") ->
        [attr, val] = String.split(expr, "<", parts: 2)

        compare_values(
          entity_attr_value(entity, String.trim(attr)),
          parse_q_value(String.trim(val))
        ) == :lt

      # Existence check: just an attribute name with no operator
      true ->
        Map.has_key?(entity, expr)
    end
  end

  defp entity_attr_value(entity, attr_name) do
    case Map.get(entity, attr_name) do
      %{"value" => value} -> value
      %{"object" => object} -> object
      other -> other
    end
  end

  defp parse_q_value(val) do
    val = String.trim(val, "\"")

    case Integer.parse(val) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(val) do
          {float, ""} -> float
          _ -> val
        end
    end
  end

  defp compare_values(nil, _), do: nil
  defp compare_values(_, nil), do: nil

  defp compare_values(a, b) when is_number(a) and is_number(b) do
    cond do
      a > b -> :gt
      a < b -> :lt
      true -> :eq
    end
  end

  defp compare_values(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a > b -> :gt
      a < b -> :lt
      true -> :eq
    end
  end

  defp compare_values(_, _), do: nil

  defp maybe_filter_by_scope(entities, nil), do: entities

  defp maybe_filter_by_scope(entities, scope_q) do
    scopes = String.split(scope_q, ",") |> Enum.map(&String.trim/1)

    Enum.filter(entities, fn entity ->
      entity_scope = Map.get(entity, "scope")

      case entity_scope do
        nil -> false
        s when is_binary(s) -> s in scopes
        ss when is_list(ss) -> Enum.any?(ss, &(&1 in scopes))
      end
    end)
  end
end
