defmodule Phaeton.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Phaeton.Repo

  alias Phaeton.Accounts.{User, UserToken, Tenant, Group, GroupMembership, ApiToken}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Returns true if the app has never been set up (no users exist).
  """
  def needs_setup? do
    !Repo.exists?(User)
  end

  @doc """
  Returns a changeset for the self-registration form (no hashing, no unique check).
  """
  def change_user_registration(user \\ %User{}, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_unique: false)
  end

  @doc """
  Registers a new user via self-registration (email + password, role=data_consumer).
  Ensures the tenant record exists.
  """
  def register_user(attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- %User{} |> User.registration_changeset(attrs) |> Repo.insert() do
        # Ensure a tenant record exists; ignore conflict if already present
        %Tenant{}
        |> Tenant.changeset(%{name: user.tenant})
        |> Repo.insert(on_conflict: :nothing)

        {:ok, user}
      end
    end)
  end

  @doc """
  Returns a changeset for the admin setup form (no hashing, no unique check).
  """
  def change_admin_setup(user \\ %User{}, attrs \\ %{}) do
    User.setup_changeset(user, attrs, hash_password: false, validate_unique: false)
  end

  @doc """
  Creates the first admin user. Returns `{:ok, user}` on success.
  """
  def register_admin(attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- %User{} |> User.setup_changeset(attrs) |> Repo.insert(),
           {:ok, _} <- %Tenant{} |> Tenant.changeset(%{name: user.tenant}) |> Repo.insert() do
        {:ok, user}
      end
    end)
  end

  ## Admin — Users

  def list_users do
    Repo.all(from u in User, order_by: [asc: u.tenant, asc: u.email])
  end

  def change_admin_create_user(user \\ %User{}, attrs \\ %{}) do
    User.admin_create_changeset(user, attrs, hash_password: false, validate_unique: false)
  end

  def admin_create_user(attrs) do
    %User{}
    |> User.admin_create_changeset(attrs)
    |> Repo.insert()
  end

  def change_admin_edit_user(user, attrs \\ %{}) do
    User.admin_edit_changeset(user, attrs)
  end

  def admin_update_user(user, attrs) do
    user
    |> User.admin_edit_changeset(attrs)
    |> Repo.update()
  end

  def admin_delete_user(user) do
    Repo.delete(user)
  end

  ## Admin — API Tokens

  def list_api_tokens(user) do
    Repo.all(from t in ApiToken, where: t.user_id == ^user.id, order_by: [desc: t.inserted_at])
  end

  def get_api_token!(id), do: Repo.get!(ApiToken, id)

  def generate_api_token(user, name) do
    {plain_token, changeset} = ApiToken.generate(user, name)

    case Repo.insert(changeset) do
      {:ok, token} -> {:ok, plain_token, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete_api_token(token), do: Repo.delete(token)

  def get_user_by_api_token(plain_token) do
    case Repo.one(ApiToken.verify_query(plain_token)) do
      nil -> nil
      %ApiToken{user: user} -> user
    end
  end

  ## Admin — Tenants

  def list_tenants do
    Repo.all(from t in Tenant, order_by: [asc: t.name])
  end

  def list_tenant_names do
    Repo.all(from t in Tenant, select: t.name, order_by: [asc: t.name])
  end

  def get_user_group_tenants(%User{id: user_id}) do
    Repo.all(
      from g in Group,
        join: m in GroupMembership,
        on: m.group_id == g.id and m.user_id == ^user_id,
        select: g.tenant,
        distinct: true
    )
  end

  def get_tenant!(id), do: Repo.get!(Tenant, id)

  def change_tenant(tenant \\ %Tenant{}, attrs \\ %{}) do
    Tenant.changeset(tenant, attrs)
  end

  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  def update_tenant(tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
  end

  def delete_tenant(tenant) do
    Repo.delete(tenant)
  end

  def tenant_user_count(tenant_name) do
    Repo.one(from u in User, where: u.tenant == ^tenant_name, select: count(u.id)) || 0
  end

  ## Admin — Groups

  def list_groups do
    Repo.all(from g in Group, order_by: [asc: g.tenant, asc: g.name])
  end

  def get_group!(id), do: Repo.get!(Group, id)

  def change_group(group \\ %Group{}, attrs \\ %{}) do
    Group.changeset(group, attrs)
  end

  def create_group(attrs) do
    %Group{}
    |> Group.changeset(attrs)
    |> Repo.insert()
  end

  def update_group(group, attrs) do
    group
    |> Group.changeset(attrs)
    |> Repo.update()
  end

  def delete_group(group) do
    Repo.delete(group)
  end

  def list_group_members(group_id) do
    Repo.all(
      from u in User,
        join: gm in GroupMembership,
        on: gm.user_id == u.id,
        where: gm.group_id == ^group_id,
        order_by: [asc: u.email]
    )
  end

  def list_users_not_in_group(group_id) do
    Repo.all(
      from u in User,
        where:
          u.id not in subquery(
            from gm in GroupMembership,
              where: gm.group_id == ^group_id,
              select: gm.user_id
          ),
        order_by: [asc: u.email]
    )
  end

  def add_group_member(group_id, user_id) do
    %GroupMembership{}
    |> GroupMembership.changeset(%{group_id: group_id, user_id: user_id})
    |> Repo.insert()
  end

  def remove_group_member(group_id, user_id) do
    Repo.delete_all(
      from gm in GroupMembership,
        where: gm.group_id == ^group_id and gm.user_id == ^user_id
    )

    :ok
  end

  def group_member_count(group_id) do
    Repo.one(from gm in GroupMembership, where: gm.group_id == ^group_id, select: count(gm.id)) ||
      0
  end

  @doc """
  Returns a changeset for changing the user email.
  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Directly updates the user's email without email confirmation tokens.
  """
  def update_user_email_direct(user, attrs) do
    user
    |> User.email_changeset(attrs)
    |> Repo.update()
  end

  def sudo_mode?(%User{} = user), do: sudo_mode?(user, -10)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns a changeset for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password and expires all existing tokens.
  """
  def update_user_password(user, attrs) do
    changeset = User.password_changeset(user, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, {user, []}}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end
end
