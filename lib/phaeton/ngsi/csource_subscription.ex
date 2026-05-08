defmodule Phaeton.NGSI.CSourceSubscription do
  @moduledoc """
  Manages NGSI-LD Context Source Subscriptions.
  """

  import Ecto.Query
  alias Phaeton.Repo
  alias Phaeton.NGSI.CSourceSubscription.CSourceSubDoc

  def create(%{"type" => "Subscription"} = data) do
    id = Map.get(data, "id", generate_id())
    data = Map.put(data, "id", id)

    attrs = %{id: id, body: Jason.encode!(data), status: "active"}

    case %CSourceSubDoc{} |> CSourceSubDoc.changeset(attrs) |> Repo.insert() do
      {:ok, _doc} -> {:ok, id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create(_), do: {:error, :bad_request}

  def get(id) do
    case Repo.get(CSourceSubDoc, id) do
      nil -> {:error, :not_found}
      doc -> {:ok, Jason.decode!(doc.body)}
    end
  end

  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    docs =
      CSourceSubDoc
      |> limit(^limit)
      |> Repo.all()
      |> Enum.map(fn doc -> Jason.decode!(doc.body) end)

    {:ok, docs}
  end

  def update(id, updates) do
    case Repo.get(CSourceSubDoc, id) do
      nil ->
        {:error, :not_found}

      doc ->
        current = Jason.decode!(doc.body)
        updated = Map.merge(current, updates)

        doc
        |> CSourceSubDoc.changeset(%{body: Jason.encode!(updated)})
        |> Repo.update()
    end
  end

  def delete(id) do
    case Repo.get(CSourceSubDoc, id) do
      nil -> {:error, :not_found}
      doc -> Repo.delete(doc)
    end
  end

  defp generate_id do
    "urn:ngsi-ld:CSourceSubscription:" <>
      Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
