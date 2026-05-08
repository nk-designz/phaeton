defmodule Phaeton.Accounts.ApiToken do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32
  @prefix "phtn_"

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :binary
    belongs_to :user, Phaeton.Accounts.User
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a new API token for the given user with the given name.
  Returns `{plain_token, changeset}` where `plain_token` starts with "phtn_"
  and must be shown to the user once — it is never stored in plaintext.
  """
  def generate(user, name) do
    raw = :crypto.strong_rand_bytes(@rand_size)
    plain_token = @prefix <> Base.url_encode64(raw, padding: false)
    token_hash = :crypto.hash(@hash_algorithm, plain_token)

    changeset =
      %__MODULE__{}
      |> change(%{name: name, token_hash: token_hash, user_id: user.id})
      |> validate_required([:name])
      |> validate_length(:name, min: 1, max: 64)
      |> unique_constraint(:token_hash)

    {plain_token, changeset}
  end

  @doc """
  Returns the query to find a token record (preloaded with user)
  matching the given plain token string.
  """
  def verify_query(plain_token) do
    token_hash = :crypto.hash(@hash_algorithm, plain_token)

    from t in __MODULE__,
      where: t.token_hash == ^token_hash,
      preload: [:user]
  end
end
