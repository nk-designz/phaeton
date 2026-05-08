defmodule Phaeton.NGSI.EntitySupervisor do
  @moduledoc """
  DynamicSupervisor for NGSI-LD entity GenServers.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_entity(entity_id, graph_name, graph) do
    child_spec = {Phaeton.NGSI.EntityServer, {entity_id, graph_name, graph}}
    target = choose_node()

    if target == node() do
      DynamicSupervisor.start_child(__MODULE__, child_spec)
    else
      :erpc.call(target, DynamicSupervisor, :start_child, [__MODULE__, child_spec])
    end
  end

  def stop_entity(graph_name) do
    case :global.whereis_name({Phaeton.NGSI.EntityRegistry, graph_name}) do
      :undefined ->
        {:error, :not_found}

      pid ->
        target = node(pid)

        if target == node() do
          DynamicSupervisor.terminate_child(__MODULE__, pid)
        else
          :erpc.call(target, DynamicSupervisor, :terminate_child, [__MODULE__, pid])
        end
    end
  end

  # Pick the node currently hosting the fewest entity servers.
  # Falls back to the local node when running standalone.
  defp choose_node do
    all_nodes = [node() | Node.list()]

    counts =
      :global.registered_names()
      |> Enum.filter(&match?({Phaeton.NGSI.EntityRegistry, _}, &1))
      |> Enum.map(&node(:global.whereis_name(&1)))
      |> Enum.frequencies()

    Enum.min_by(all_nodes, fn n -> Map.get(counts, n, 0) end)
  end
end
