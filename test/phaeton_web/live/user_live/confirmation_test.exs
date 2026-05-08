defmodule PhaetonWeb.UserLive.ConfirmationTest do
  use PhaetonWeb.ConnCase, async: false

  # Confirmation is disabled. The LiveView module exists but only redirects.
  # The /users/confirm/:token route has been removed from the router.
end
