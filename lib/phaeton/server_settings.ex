defmodule Phaeton.ServerSettings do
  @moduledoc """
  Key/value server-wide settings stored in the database.
  Provides typed helpers for each setting.
  """

  import Ecto.Query
  alias Phaeton.Repo

  defmodule Setting do
    use Ecto.Schema
    import Ecto.Changeset

    schema "server_settings" do
      field :key, :string
      field :value, :string

      timestamps(type: :utc_datetime)
    end

    def changeset(setting, attrs) do
      setting
      |> cast(attrs, [:key, :value])
      |> validate_required([:key, :value])
      |> unique_constraint(:key)
    end
  end

  @doc "Returns true when public self-registration is enabled."
  def registration_enabled? do
    get("registration_enabled") == "true"
  end

  @doc "Enables or disables public self-registration."
  def set_registration_enabled(enabled) when is_boolean(enabled) do
    put("registration_enabled", to_string(enabled))
  end

  # ── private helpers ───────────────────────────────────────────────────────

  defp get(key) do
    case Repo.one(from s in Setting, where: s.key == ^key) do
      nil -> nil
      %Setting{value: v} -> v
    end
  end

  defp put(key, value) do
    case Repo.one(from s in Setting, where: s.key == ^key) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{key: key, value: value})
        |> Repo.insert()

      setting ->
        setting
        |> Setting.changeset(%{value: value})
        |> Repo.update()
    end
  end
end
