defmodule Phaeton.NGSI.Temporal do
  @moduledoc """
  Manages temporal representation of NGSI-LD entities.
  Stores historical attribute values indexed by observedAt timestamps.
  """

  import Ecto.Query
  alias Phaeton.Repo
  alias Phaeton.Store.TemporalAttribute
  alias Phaeton.NGSI.Entity

  @doc """
  Upsert a temporal entity representation.
  Extracts all attributes with observedAt and stores them as temporal instances.
  """
  def upsert_temporal(%{"id" => entity_id} = entity_data) do
    attrs =
      entity_data
      |> Map.drop(["id", "type", "@context", "scope", "_json", "_format"])
      |> Enum.flat_map(fn {attr_name, attr_value} ->
        extract_temporal_instances(entity_id, attr_name, attr_value)
      end)

    Repo.transaction(fn ->
      Enum.each(attrs, fn attr_map ->
        %TemporalAttribute{}
        |> TemporalAttribute.changeset(attr_map)
        |> Repo.insert(
          on_conflict: {:replace, [:value, :object_value, :datatype, :attribute_type]},
          conflict_target: [:instance_id]
        )
      end)
    end)

    {:ok, entity_id}
  end

  def upsert_temporal(_), do: {:error, :bad_request}

  @doc """
  Query temporal entities with optional time filters.
  """
  def query_temporal(params \\ %{}) do
    type_filter = Map.get(params, "type")
    id_filter = Map.get(params, "id")
    time_rel = Map.get(params, "timerel")
    time_at = Map.get(params, "timeAt")
    end_time_at = Map.get(params, "endTimeAt")
    limit = parse_int(Map.get(params, "limit"), 100)
    offset = parse_int(Map.get(params, "offset"), 0)

    query =
      TemporalAttribute
      |> maybe_filter_entity_id(id_filter)
      |> maybe_filter_time(time_rel, time_at, end_time_at)
      |> order_by([t], asc: t.entity_id, desc: t.observed_at)

    all_entries = Repo.all(query)

    # Group by entity_id and reconstruct temporal entities
    entities =
      all_entries
      |> Enum.group_by(& &1.entity_id)
      |> maybe_filter_entity_type(type_filter)
      |> Enum.map(fn {entity_id, entries} ->
        build_temporal_entity(entity_id, entries)
      end)
      |> Enum.drop(offset)
      |> Enum.take(limit)

    {:ok, entities}
  end

  @doc """
  Retrieve a single temporal entity.
  """
  def retrieve_temporal(entity_id, params \\ %{}) do
    time_rel = Map.get(params, "timerel")
    time_at = Map.get(params, "timeAt")
    end_time_at = Map.get(params, "endTimeAt")

    query =
      TemporalAttribute
      |> where([t], t.entity_id == ^entity_id)
      |> maybe_filter_time(time_rel, time_at, end_time_at)
      |> order_by([t], desc: t.observed_at)

    entries = Repo.all(query)

    if entries == [] do
      {:error, :not_found}
    else
      {:ok, build_temporal_entity(entity_id, entries)}
    end
  end

  @doc """
  Delete all temporal data for an entity.
  """
  def delete_temporal(entity_id) do
    result =
      TemporalAttribute
      |> where([t], t.entity_id == ^entity_id)
      |> Repo.delete_all()

    case result do
      {0, _} -> {:error, :not_found}
      {_n, _} -> :ok
    end
  end

  @doc """
  Append temporal attribute instances.
  """
  def append_temporal_attrs(entity_id, attrs_map) do
    instances =
      attrs_map
      |> Map.drop(["id", "type", "@context", "_json", "_format"])
      |> Enum.flat_map(fn {attr_name, attr_value} ->
        extract_temporal_instances(entity_id, attr_name, attr_value)
      end)

    if instances == [] do
      {:error, :bad_request}
    else
      Repo.transaction(fn ->
        Enum.each(instances, fn attr_map ->
          %TemporalAttribute{}
          |> TemporalAttribute.changeset(attr_map)
          |> Repo.insert!(
            on_conflict: {:replace, [:value, :object_value, :datatype, :attribute_type]},
            conflict_target: [:instance_id]
          )
        end)
      end)
    end
  end

  @doc """
  Delete a temporal attribute's instances.
  """
  def delete_temporal_attr(entity_id, attr_id, params \\ %{}) do
    ngsild_base = "https://uri.etsi.org/ngsi-ld/"
    attr_iri = if String.contains?(attr_id, "://"), do: attr_id, else: ngsild_base <> attr_id

    query =
      TemporalAttribute
      |> where([t], t.entity_id == ^entity_id and t.attribute_name == ^attr_iri)

    query =
      case Map.get(params, "deleteAll") do
        "true" ->
          query

        _ ->
          case Map.get(params, "datasetId") do
            nil -> query
            _ -> query
          end
      end

    case Repo.delete_all(query) do
      {0, _} -> {:error, :not_found}
      {_n, _} -> :ok
    end
  end

  @doc """
  Update a specific temporal attribute instance.
  """
  def update_temporal_attr_instance(entity_id, _attr_id, instance_id, fragment) do
    case Repo.get_by(TemporalAttribute, instance_id: instance_id, entity_id: entity_id) do
      nil ->
        {:error, :not_found}

      record ->
        value = extract_value(fragment)

        record
        |> TemporalAttribute.changeset(%{value: value})
        |> Repo.update()
    end
  end

  @doc """
  Delete a specific temporal attribute instance.
  """
  def delete_temporal_attr_instance(entity_id, _attr_id, instance_id) do
    case Repo.get_by(TemporalAttribute, instance_id: instance_id, entity_id: entity_id) do
      nil -> {:error, :not_found}
      record -> Repo.delete(record)
    end
  end

  # Private helpers

  defp extract_temporal_instances(entity_id, attr_name, instances) when is_list(instances) do
    Enum.flat_map(instances, fn instance ->
      extract_temporal_instances(entity_id, attr_name, instance)
    end)
  end

  defp extract_temporal_instances(entity_id, attr_name, %{"type" => type} = attr) do
    ngsild_base = "https://uri.etsi.org/ngsi-ld/"

    attr_iri =
      if String.contains?(attr_name, "://"), do: attr_name, else: ngsild_base <> attr_name

    observed_at =
      case Map.get(attr, "observedAt") do
        nil ->
          DateTime.utc_now()

        ts ->
          case DateTime.from_iso8601(ts) do
            {:ok, dt, _} -> dt
            _ -> DateTime.utc_now()
          end
      end

    instance_id = Map.get(attr, "instanceId", generate_instance_id())
    value = extract_value(attr)

    [
      %{
        entity_id: entity_id,
        attribute_name: attr_iri,
        instance_id: instance_id,
        observed_at: observed_at,
        attribute_type: type,
        value: value,
        object_value: if(type == "Relationship", do: Map.get(attr, "object")),
        datatype: nil
      }
    ]
  end

  defp extract_temporal_instances(_, _, _), do: []

  defp extract_value(%{"type" => "Relationship", "object" => obj}), do: obj

  defp extract_value(%{"type" => "GeoProperty", "value" => val}) when is_map(val),
    do: Jason.encode!(val)

  defp extract_value(%{"value" => val}) when is_binary(val), do: val
  defp extract_value(%{"value" => val}), do: Jason.encode!(val)
  defp extract_value(val) when is_map(val), do: Jason.encode!(val)

  defp build_temporal_entity(entity_id, entries) do
    # Get entity type from current entity if available
    entity_type =
      case Phaeton.Store.get_triples_by_subject(entity_id) do
        [] ->
          "Thing"

        triples ->
          rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

          case Enum.find(triples, fn t -> t.predicate == rdf_type end) do
            nil -> "Thing"
            t -> Entity.compact_iri(t.object_value)
          end
      end

    # Group entries by attribute name
    attrs =
      entries
      |> Enum.group_by(& &1.attribute_name)
      |> Enum.into(%{}, fn {attr_iri, instances} ->
        attr_name = Entity.compact_iri(attr_iri)

        values =
          Enum.map(instances, fn inst ->
            base = %{
              "type" => inst.attribute_type,
              "instanceId" => inst.instance_id,
              "observedAt" => DateTime.to_iso8601(inst.observed_at)
            }

            case inst.attribute_type do
              "Relationship" ->
                Map.put(base, "object", inst.object_value || inst.value)

              "GeoProperty" ->
                geo =
                  case Jason.decode(inst.value) do
                    {:ok, g} -> g
                    _ -> inst.value
                  end

                Map.put(base, "value", geo)

              _ ->
                val = decode_temporal_value(inst.value)
                Map.put(base, "value", val)
            end
          end)

        {attr_name, values}
      end)

    Map.merge(%{"id" => entity_id, "type" => entity_type}, attrs)
  end

  defp decode_temporal_value(val) do
    case Jason.decode(val) do
      {:ok, decoded} ->
        decoded

      _ ->
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
  end

  defp maybe_filter_entity_id(query, nil), do: query

  defp maybe_filter_entity_id(query, id) do
    ids = String.split(id, ",")
    where(query, [t], t.entity_id in ^ids)
  end

  defp maybe_filter_time(query, nil, _, _), do: query
  defp maybe_filter_time(query, _timerel, nil, _), do: query

  defp maybe_filter_time(query, "after", time_at, _) do
    case DateTime.from_iso8601(time_at) do
      {:ok, dt, _} -> where(query, [t], t.observed_at > ^dt)
      _ -> query
    end
  end

  defp maybe_filter_time(query, "before", time_at, _) do
    case DateTime.from_iso8601(time_at) do
      {:ok, dt, _} -> where(query, [t], t.observed_at < ^dt)
      _ -> query
    end
  end

  defp maybe_filter_time(query, "between", time_at, end_time_at) do
    with {:ok, start_dt, _} <- DateTime.from_iso8601(time_at),
         {:ok, end_dt, _} <- DateTime.from_iso8601(end_time_at || time_at) do
      where(query, [t], t.observed_at >= ^start_dt and t.observed_at <= ^end_dt)
    else
      _ -> query
    end
  end

  defp maybe_filter_time(query, _, _, _), do: query

  defp maybe_filter_entity_type(grouped, nil), do: grouped |> Map.to_list()

  defp maybe_filter_entity_type(grouped, type_filter) do
    types = String.split(type_filter, ",")
    rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    ngsild_base = "https://uri.etsi.org/ngsi-ld/"

    type_iris =
      Enum.map(types, fn t ->
        if String.contains?(t, "://"), do: t, else: ngsild_base <> t
      end)

    grouped
    |> Enum.filter(fn {entity_id, _entries} ->
      case Phaeton.Store.get_triples_by_subject(entity_id) do
        [] ->
          false

        triples ->
          Enum.any?(triples, fn t ->
            t.predicate == rdf_type and t.object_value in type_iris
          end)
      end
    end)
  end

  defp generate_instance_id do
    "urn:ngsi-ld:TemporalInstance:" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
