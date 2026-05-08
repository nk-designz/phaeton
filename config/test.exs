import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :phaeton, Phaeton.Repo,
  database: Path.expand("../phaeton_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  journal_mode: :wal,
  busy_timeout: 5000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :phaeton, PhaetonWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7rs4mU40yns+mcRzdAOUHZQujnIUbTs83P6MCeOjLK3wG+sNReR2uW5PZQoXrbYz",
  server: false

# In test we don't send emails

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Disable notification delivery in tests to avoid DB sandbox issues
config :phaeton, enable_notifications: false

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
