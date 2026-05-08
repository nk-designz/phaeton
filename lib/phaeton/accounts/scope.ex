defmodule Phaeton.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller.

  Carries identity (user, role, tenant) plus authorization helpers:
  - `allowed_tenants` — list of tenant names this user may access (`:all` for admins)
  - `active_tenant`   — the currently selected tenant for UI filtering;
                         `:all` for admins who want cross-tenant view
  """

  alias Phaeton.Accounts.User

  defstruct user: nil,
            tenant: "default",
            role: "data_consumer",
            allowed_tenants: [],
            active_tenant: nil

  @doc """
  Builds a scope for the given user, optionally with a session-persisted active tenant.
  """
  def for_user(user, session_active_tenant \\ nil)

  def for_user(%User{role: "admin"} = user, session_active_tenant) do
    own_tenant = user.tenant || "default"
    all_names = Phaeton.Accounts.list_tenant_names()

    active =
      if is_binary(session_active_tenant) and session_active_tenant != "",
        do: session_active_tenant,
        else: :all

    %__MODULE__{
      user: user,
      tenant: own_tenant,
      role: "admin",
      allowed_tenants: all_names,
      active_tenant: active
    }
  end

  def for_user(%User{} = user, session_active_tenant) do
    own_tenant = user.tenant || "default"
    group_tenants = Phaeton.Accounts.get_user_group_tenants(user)
    allowed = [own_tenant | group_tenants] |> Enum.uniq() |> Enum.sort()

    active =
      if is_binary(session_active_tenant) and session_active_tenant in allowed,
        do: session_active_tenant,
        else: own_tenant

    %__MODULE__{
      user: user,
      tenant: own_tenant,
      role: user.role || "data_consumer",
      allowed_tenants: allowed,
      active_tenant: active
    }
  end

  def for_user(nil, _), do: nil

  def can_write?(%__MODULE__{role: role}) when role in ~w(admin agent data_provider), do: true
  def can_write?(_), do: false

  def is_admin?(%__MODULE__{role: "admin"}), do: true
  def is_admin?(_), do: false
end
