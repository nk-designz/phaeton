defmodule PhaetonWeb.UserLive.RegistrationTest do
  use PhaetonWeb.ConnCase, async: false

  # Public registration is disabled. The LiveView module redirects to login.
  # The /users/register route has been removed from the router.
end
