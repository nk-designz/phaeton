defmodule PhaetonWeb.API.InfoController do
  use PhaetonWeb, :controller

  # GET /ngsi-ld/v1/info/sourceIdentity
  def source_identity(conn, _params) do
    json(conn, %{
      "id" => "urn:ngsi-ld:ContextSourceIdentity:phaeton",
      "type" => "ContextSourceIdentity",
      "contextSourceType" => "ContextBroker",
      "contextSourceIdentity" =>
        Application.get_env(:phaeton, :source_identity, "urn:ngsi-ld:ContextSource:phaeton"),
      "contextSourceAlias" => "Phaeton Context Broker",
      "supportedNGSILDVersion" => "1.8",
      "tenantList" => [],
      "contextSourceRegistrationMode" => "inclusive"
    })
  end
end
