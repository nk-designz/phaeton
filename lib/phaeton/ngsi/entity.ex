defmodule Phaeton.NGSI.Entity do
  @moduledoc """
  Converts between NGSI-LD JSON entity representation and RDF graphs.
  Handles the core NGSI-LD data model: Properties, Relationships,
  GeoProperties, and their sub-attributes.
  """

  @ngsild_base "https://uri.etsi.org/ngsi-ld/"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @xsd_datetime "http://www.w3.org/2001/XMLSchema#dateTime"
  @xsd_double "http://www.w3.org/2001/XMLSchema#double"
  @xsd_integer "http://www.w3.org/2001/XMLSchema#integer"
  @xsd_boolean "http://www.w3.org/2001/XMLSchema#boolean"

  @system_attrs ~w(createdAt modifiedAt deletedAt)
  @reserved_keys ~w(id type scope @context _json _format)

  @doc """
  Convert an NGSI-LD JSON entity map into an RDF.Graph.
  The entity_id is used as both the graph name and subject.
  """
  def ngsi_to_graph(%{"id" => entity_id, "type" => entity_type} = entity) do
    subject = RDF.IRI.new!(entity_id)
    graph_name = RDF.IRI.new!(entity_id)

    type_iri = expand_type(entity_type)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    base_triples = [
      {subject, RDF.IRI.new!(@rdf_type), RDF.IRI.new!(type_iri)},
      {subject, RDF.IRI.new!(@ngsild_base <> "createdAt"),
       RDF.Literal.new(now, datatype: RDF.IRI.new!(@xsd_datetime))},
      {subject, RDF.IRI.new!(@ngsild_base <> "modifiedAt"),
       RDF.Literal.new(now, datatype: RDF.IRI.new!(@xsd_datetime))}
    ]

    scope_triples =
      case Map.get(entity, "scope") do
        nil ->
          []

        scope when is_binary(scope) ->
          [{subject, RDF.IRI.new!(@ngsild_base <> "scope"), RDF.XSD.String.new(scope)}]

        scopes when is_list(scopes) ->
          Enum.map(scopes, fn s ->
            {subject, RDF.IRI.new!(@ngsild_base <> "scope"), RDF.XSD.String.new(s)}
          end)
      end

    attr_triples =
      entity
      |> Map.drop(@reserved_keys ++ @system_attrs)
      |> Enum.flat_map(fn {attr_name, attr_value} ->
        attribute_to_triples(subject, attr_name, attr_value)
      end)

    all_triples = base_triples ++ scope_triples ++ attr_triples
    RDF.Graph.new(init: all_triples, name: graph_name)
  end

  @doc """
  Convert an RDF.Graph back into an NGSI-LD JSON entity map.
  """
  def graph_to_ngsi(%RDF.Graph{} = graph, entity_id) do
    subject = RDF.IRI.new!(entity_id)

    case RDF.Graph.get(graph, subject) do
      nil ->
        nil

      description ->
        type = extract_type(description)
        base = %{"id" => entity_id, "type" => type}

        attrs =
          description
          |> RDF.Description.predicates()
          |> Enum.reject(fn pred ->
            pred_str = to_string(pred)

            pred_str == @rdf_type or
              String.starts_with?(pred_str, @ngsild_base <> "createdAt") or
              String.starts_with?(pred_str, @ngsild_base <> "modifiedAt") or
              String.starts_with?(pred_str, @ngsild_base <> "deletedAt") or
              pred_str == @ngsild_base <> "scope" or
              String.contains?(pred_str, "#type") or
              String.contains?(pred_str, "#observedAt") or
              String.contains?(pred_str, "#unitCode") or
              String.contains?(pred_str, "#datasetId")
          end)
          |> Enum.reduce(%{}, fn predicate, acc ->
            attr_name = compact_iri(to_string(predicate))
            objects = RDF.Description.get(description, predicate)
            attr_value = triples_to_attribute(predicate, objects, graph, subject)
            Map.put(acc, attr_name, attr_value)
          end)

        # Add system attrs
        sys_attrs =
          Enum.reduce(~w(createdAt modifiedAt), %{}, fn attr, acc ->
            iri = RDF.IRI.new!(@ngsild_base <> attr)

            case RDF.Description.get(description, iri) do
              nil -> acc
              [val | _] -> Map.put(acc, attr, RDF.Literal.lexical(val))
            end
          end)

        # Add scope
        scope_attrs =
          case RDF.Description.get(description, RDF.IRI.new!(@ngsild_base <> "scope")) do
            nil -> %{}
            [single] -> %{"scope" => RDF.Literal.lexical(single)}
            multiple -> %{"scope" => Enum.map(multiple, &RDF.Literal.lexical/1)}
          end

        Map.merge(base, attrs) |> Map.merge(sys_attrs) |> Map.merge(scope_attrs)
    end
  end

  @doc """
  Convert an NGSI-LD attribute fragment (without entity id/type) into RDF triples.
  """
  def fragment_to_triples(entity_id, attrs_map) do
    subject = RDF.IRI.new!(entity_id)

    triples =
      attrs_map
      |> Map.drop(@reserved_keys)
      |> Enum.flat_map(fn {attr_name, attr_value} ->
        attribute_to_triples(subject, attr_name, attr_value)
      end)

    RDF.Graph.new(init: triples, name: RDF.IRI.new!(entity_id))
  end

  # Private: Convert a single NGSI-LD attribute to RDF triples
  defp attribute_to_triples(subject, attr_name, %{"type" => "Property", "value" => value} = attr) do
    predicate = expand_attr(attr_name)
    pred_iri = RDF.IRI.new!(predicate)

    value_triple = {subject, pred_iri, encode_value(value)}

    type_triple =
      {subject, RDF.IRI.new!(predicate <> "#type"), RDF.IRI.new!(@ngsild_base <> "Property")}

    observed_at_triples =
      case Map.get(attr, "observedAt") do
        nil ->
          []

        ts ->
          [
            {subject, RDF.IRI.new!(predicate <> "#observedAt"),
             RDF.Literal.new(ts, datatype: RDF.IRI.new!(@xsd_datetime))}
          ]
      end

    unit_code_triples =
      case Map.get(attr, "unitCode") do
        nil -> []
        uc -> [{subject, RDF.IRI.new!(predicate <> "#unitCode"), RDF.XSD.String.new(uc)}]
      end

    dataset_id_triples =
      case Map.get(attr, "datasetId") do
        nil -> []
        did -> [{subject, RDF.IRI.new!(predicate <> "#datasetId"), RDF.IRI.new!(did)}]
      end

    [value_triple, type_triple] ++ observed_at_triples ++ unit_code_triples ++ dataset_id_triples
  end

  defp attribute_to_triples(subject, attr_name, %{"type" => "Relationship", "object" => object}) do
    predicate = expand_attr(attr_name)
    pred_iri = RDF.IRI.new!(predicate)
    object_iri = RDF.IRI.new!(object)

    [
      {subject, pred_iri, object_iri},
      {subject, RDF.IRI.new!(predicate <> "#type"), RDF.IRI.new!(@ngsild_base <> "Relationship")}
    ]
  end

  defp attribute_to_triples(subject, attr_name, %{"type" => "GeoProperty", "value" => value}) do
    predicate = expand_attr(attr_name)
    pred_iri = RDF.IRI.new!(predicate)
    geo_json = Jason.encode!(value)

    [
      {subject, pred_iri, RDF.XSD.String.new(geo_json)},
      {subject, RDF.IRI.new!(predicate <> "#type"), RDF.IRI.new!(@ngsild_base <> "GeoProperty")}
    ]
  end

  defp attribute_to_triples(subject, attr_name, %{
         "type" => "LanguageProperty",
         "languageMap" => lang_map
       }) do
    predicate = expand_attr(attr_name)
    pred_iri = RDF.IRI.new!(predicate)

    lang_triples =
      Enum.map(lang_map, fn {lang, value} ->
        {subject, pred_iri, RDF.LangString.new(value, language: lang)}
      end)

    type_triple =
      {subject, RDF.IRI.new!(predicate <> "#type"),
       RDF.IRI.new!(@ngsild_base <> "LanguageProperty")}

    [type_triple | lang_triples]
  end

  # Fallback: treat as a simple property with inline value
  defp attribute_to_triples(subject, attr_name, value) when not is_map(value) do
    predicate = expand_attr(attr_name)
    pred_iri = RDF.IRI.new!(predicate)
    [{subject, pred_iri, encode_value(value)}]
  end

  defp attribute_to_triples(_subject, _attr_name, _value), do: []

  # Convert NGSI-LD value to RDF literal
  defp encode_value(value) when is_binary(value), do: RDF.XSD.String.new(value)
  defp encode_value(value) when is_integer(value), do: RDF.XSD.Integer.new(value)
  defp encode_value(value) when is_float(value), do: RDF.XSD.Double.new(value)
  defp encode_value(true), do: RDF.XSD.Boolean.new(true)
  defp encode_value(false), do: RDF.XSD.Boolean.new(false)
  defp encode_value(value) when is_map(value), do: RDF.XSD.String.new(Jason.encode!(value))
  defp encode_value(value) when is_list(value), do: RDF.XSD.String.new(Jason.encode!(value))
  defp encode_value(nil), do: RDF.XSD.String.new("")

  # Extract entity type from RDF description
  defp extract_type(description) do
    case RDF.Description.get(description, RDF.IRI.new!(@rdf_type)) do
      nil -> "Thing"
      [type_iri | _] -> compact_iri(to_string(type_iri))
    end
  end

  # Convert RDF objects back to NGSI-LD attribute representation
  defp triples_to_attribute(predicate, objects, graph, subject) do
    pred_str = to_string(predicate)
    type_pred = RDF.IRI.new!(pred_str <> "#type")
    observed_pred = RDF.IRI.new!(pred_str <> "#observedAt")
    unit_pred = RDF.IRI.new!(pred_str <> "#unitCode")
    dataset_pred = RDF.IRI.new!(pred_str <> "#datasetId")

    description = RDF.Graph.get(graph, subject)

    attr_type =
      case description do
        nil ->
          nil

        desc ->
          case RDF.Description.get(desc, type_pred) do
            nil -> nil
            [type_iri | _] -> to_string(type_iri)
          end
      end

    base_attr =
      cond do
        attr_type == @ngsild_base <> "Relationship" ->
          object_val =
            case objects do
              [%RDF.IRI{} = iri | _] -> to_string(iri)
              [other | _] -> RDF.Literal.lexical(other)
            end

          %{"type" => "Relationship", "object" => object_val}

        attr_type == @ngsild_base <> "GeoProperty" ->
          geo_val =
            case objects do
              [lit | _] ->
                case Jason.decode(RDF.Literal.lexical(lit)) do
                  {:ok, geo} -> geo
                  _ -> RDF.Literal.lexical(lit)
                end
            end

          %{"type" => "GeoProperty", "value" => geo_val}

        attr_type == @ngsild_base <> "LanguageProperty" ->
          lang_map =
            Enum.reduce(objects, %{}, fn obj, acc ->
              case RDF.Literal.language(obj) do
                nil -> acc
                lang -> Map.put(acc, to_string(lang), RDF.Literal.lexical(obj))
              end
            end)

          %{"type" => "LanguageProperty", "languageMap" => lang_map}

        true ->
          # Default: Property
          value = decode_rdf_value(objects)
          %{"type" => "Property", "value" => value}
      end

    # Reconstruct metadata: observedAt, unitCode
    base_attr =
      case description && RDF.Description.get(description, observed_pred) do
        nil -> base_attr
        [ts | _] -> Map.put(base_attr, "observedAt", RDF.Literal.lexical(ts))
        _ -> base_attr
      end

    case description && RDF.Description.get(description, unit_pred) do
      nil -> base_attr
      [uc | _] -> Map.put(base_attr, "unitCode", RDF.Literal.lexical(uc))
      _ -> base_attr
    end
    |> then(fn attr ->
      case description && RDF.Description.get(description, dataset_pred) do
        nil -> attr
        [did | _] -> Map.put(attr, "datasetId", to_string(did))
        _ -> attr
      end
    end)
  end

  defp decode_rdf_value([single]) do
    decode_single_value(single)
  end

  defp decode_rdf_value(multiple) when is_list(multiple) do
    Enum.map(multiple, &decode_single_value/1)
  end

  defp decode_single_value(%RDF.IRI{} = iri), do: to_string(iri)

  defp decode_single_value(%RDF.Literal{} = lit) do
    datatype = to_string(RDF.Literal.datatype_id(lit))

    cond do
      datatype == @xsd_integer ->
        case Integer.parse(RDF.Literal.lexical(lit)) do
          {int, _} -> int
          :error -> RDF.Literal.lexical(lit)
        end

      datatype == @xsd_double ->
        case Float.parse(RDF.Literal.lexical(lit)) do
          {float, _} -> float
          :error -> RDF.Literal.lexical(lit)
        end

      datatype == @xsd_boolean ->
        RDF.Literal.lexical(lit) == "true"

      true ->
        RDF.Literal.lexical(lit)
    end
  end

  defp decode_single_value(other), do: to_string(other)

  # Expand short attribute names to full IRIs
  defp expand_attr(name) do
    if String.contains?(name, "://") do
      name
    else
      @ngsild_base <> name
    end
  end

  defp expand_type(type) do
    if String.contains?(type, "://") do
      type
    else
      @ngsild_base <> type
    end
  end

  @doc """
  Compact a full IRI to a short name if it starts with known prefixes.
  """
  def compact_iri(iri) do
    cond do
      String.starts_with?(iri, @ngsild_base) ->
        String.replace_prefix(iri, @ngsild_base, "")

      true ->
        iri
    end
  end
end
