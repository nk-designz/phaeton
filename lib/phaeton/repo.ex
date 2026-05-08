defmodule Phaeton.Repo do
  use Ecto.Repo,
    otp_app: :phaeton,
    adapter: Ecto.Adapters.SQLite3
end
