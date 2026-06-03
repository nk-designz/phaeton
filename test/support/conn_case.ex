defmodule PhaetonWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use PhaetonWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint PhaetonWeb.Endpoint

      use PhaetonWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import PhaetonWeb.ConnCase
    end
  end

  setup tags do
    Phaeton.DataCase.setup_sandbox(tags)
    # Ensure at least one user exists so CheckSetup does not redirect to /setup.
    # Direct inserts are used here to avoid nested transactions (Repo.transact inside
    # the sandbox's outer transaction causes "Database busy" on SQLite).
    tenant_name = "conn-case-#{System.unique_integer([:positive])}"

    {:ok, _} =
      %Phaeton.Accounts.Tenant{}
      |> Phaeton.Accounts.Tenant.changeset(%{name: tenant_name})
      |> Phaeton.Repo.insert()

    {:ok, _} =
      %Phaeton.Accounts.User{}
      |> Phaeton.Accounts.User.setup_changeset(%{
        email: "setup-#{System.unique_integer()}@example.com",
        password: "hello world!",
        tenant: tenant_name
      })
      |> Phaeton.Repo.insert()

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Logs the given user into the conn and returns the updated conn.

  Puts the user session token directly without issuing a redirect.
  Accepts `token_authenticated_at:` option to override the session
  authenticated_at timestamp (used for sudo-mode tests).
  """
  def log_in_user(conn, user, opts \\ []) do
    user =
      case opts[:token_authenticated_at] do
        nil -> user
        dt -> %{user | authenticated_at: dt}
      end

    token = Phaeton.Accounts.generate_user_session_token(user)
    live_socket_id = "users_sessions:#{Base.url_encode64(token)}"

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
    |> Plug.Conn.put_session(:live_socket_id, live_socket_id)
  end

  @doc """
  Adds a valid Bearer API token to the conn's Authorization header.

  Creates a temporary user and generates an API token for it.
  Use this in API controller tests that require authentication.
  """
  def put_api_token(conn) do
    user = Phaeton.AccountsFixtures.unconfirmed_user_fixture(%{})
    {:ok, plain_token, _} = Phaeton.Accounts.generate_api_token(user, "test-token")
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{plain_token}")
  end
end
