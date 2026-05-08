defmodule Phaeton.NGSI.EntityServer do
  @moduledoc """
  GenServer managing a single NGSI-LD entity's RDF graph in memory.
  Each entity gets its own process, registered via the entity Registry.
  The graph is persisted to the triple store on mutations.
  """

  use GenServer, restart: :transient

  alias Phaeton.Store

  # Client API

  def start_link({entity_id, graph_name, graph}) do
    GenServer.start_link(__MODULE__, {entity_id, graph_name, graph}, name: via(graph_name))
  end

  def get_graph(graph_name) do
    GenServer.call(via(graph_name), :get_graph)
  end

  def get_entity(graph_name) do
    GenServer.call(via(graph_name), :get_entity)
  end

  def update_graph(graph_name, update_fn) do
    GenServer.call(via(graph_name), {:update_graph, update_fn})
  end

  def replace_graph(graph_name, graph) do
    GenServer.call(via(graph_name), {:replace_graph, graph})
  end

  def merge_entity(graph_name, fragment_graph) do
    GenServer.call(via(graph_name), {:merge, fragment_graph})
  end

  def append_attrs(graph_name, attrs_graph, opts \\ []) do
    GenServer.call(via(graph_name), {:append_attrs, attrs_graph, opts})
  end

  def update_attrs(graph_name, attrs_graph) do
    GenServer.call(via(graph_name), {:update_attrs, attrs_graph})
  end

  def delete_attr(graph_name, attr_iri) do
    GenServer.call(via(graph_name), {:delete_attr, attr_iri})
  end

  def stop(graph_name) do
    GenServer.stop(via(graph_name))
  end

  def alive?(graph_name) do
    :global.whereis_name({Phaeton.NGSI.EntityRegistry, graph_name}) != :undefined
  end

  defp via(graph_name) do
    {:global, {Phaeton.NGSI.EntityRegistry, graph_name}}
  end

  # Server callbacks

  @impl true
  def init({entity_id, graph_name, graph}) do
    {:ok, %{entity_id: entity_id, graph_name: graph_name, graph: graph}}
  end

  @impl true
  def handle_call(:get_graph, _from, state) do
    {:reply, {:ok, state.graph}, state}
  end

  @impl true
  def handle_call(:get_entity, _from, state) do
    entity = Phaeton.NGSI.Entity.graph_to_ngsi(state.graph, state.entity_id)
    {:reply, {:ok, entity}, state}
  end

  @impl true
  def handle_call({:replace_graph, new_graph}, _from, state) do
    new_graph = touch_modified_at(new_graph, state.entity_id)

    case persist_graph(state.entity_id, state.graph_name, new_graph) do
      :ok ->
        {:reply, :ok, %{state | graph: new_graph}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_graph, update_fn}, _from, state) do
    new_graph =
      state.graph
      |> update_fn.()
      |> touch_modified_at(state.entity_id)

    case persist_graph(state.entity_id, state.graph_name, new_graph) do
      :ok ->
        {:reply, {:ok, new_graph}, %{state | graph: new_graph}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:merge, fragment_graph}, _from, state) do
    new_graph =
      state.graph
      |> RDF.Graph.put_properties(fragment_graph)
      |> touch_modified_at(state.entity_id)

    case persist_graph(state.entity_id, state.graph_name, new_graph) do
      :ok ->
        {:reply, :ok, %{state | graph: new_graph}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:append_attrs, attrs_graph, opts}, _from, state) do
    no_overwrite = Keyword.get(opts, :no_overwrite, false)
    subject_iri = RDF.IRI.new!(state.entity_id)

    new_graph =
      if no_overwrite do
        # Only add predicates that don't already exist
        existing_desc = RDF.Graph.get(state.graph, subject_iri)

        RDF.Graph.triples(attrs_graph)
        |> Enum.reduce(state.graph, fn {_s, predicate, _o} = triple, acc ->
          if existing_desc && RDF.Description.get(existing_desc, predicate) do
            acc
          else
            RDF.Graph.add(acc, triple)
          end
        end)
      else
        RDF.Graph.put_properties(state.graph, attrs_graph)
      end

    new_graph = touch_modified_at(new_graph, state.entity_id)

    case persist_graph(state.entity_id, state.graph_name, new_graph) do
      :ok ->
        {:reply, :ok, %{state | graph: new_graph}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_attrs, attrs_graph}, _from, state) do
    new_graph =
      state.graph
      |> RDF.Graph.put_properties(attrs_graph)
      |> touch_modified_at(state.entity_id)

    case persist_graph(state.entity_id, state.graph_name, new_graph) do
      :ok ->
        {:reply, :ok, %{state | graph: new_graph}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete_attr, attr_iri}, _from, state) do
    subject_iri = RDF.IRI.new!(state.entity_id)

    # Delete main predicate and all meta-predicates (#type, #observedAt, #unitCode, #datasetId)
    meta_suffixes = ["#type", "#observedAt", "#unitCode", "#datasetId"]

    new_graph =
      Enum.reduce([attr_iri | Enum.map(meta_suffixes, &(attr_iri <> &1))], state.graph, fn iri,
                                                                                           g ->
        RDF.Graph.delete_predications(g, {subject_iri, RDF.IRI.new!(iri)})
      end)
      |> touch_modified_at(state.entity_id)

    case persist_graph(state.entity_id, state.graph_name, new_graph) do
      :ok ->
        {:reply, :ok, %{state | graph: new_graph}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @ngsild_base "https://uri.etsi.org/ngsi-ld/"
  @xsd_datetime "http://www.w3.org/2001/XMLSchema#dateTime"

  defp touch_modified_at(graph, entity_id) do
    subject = RDF.IRI.new!(entity_id)
    modified_pred = RDF.IRI.new!(@ngsild_base <> "modifiedAt")
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    now_lit = RDF.Literal.new(now, datatype: RDF.IRI.new!(@xsd_datetime))

    graph
    |> RDF.Graph.delete_predications({subject, modified_pred})
    |> RDF.Graph.add({subject, modified_pred, now_lit})
  end

  defp persist_graph(entity_id, graph_name, graph) do
    alias Phaeton.Repo

    Repo.transaction(fn ->
      Store.delete_triples_by_subject_and_graph(entity_id, graph_name)
      triple_attrs = Store.graph_to_triple_attrs(graph, graph_name)

      case Store.insert_triples_no_tx(triple_attrs) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
