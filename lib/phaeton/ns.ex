defmodule Phaeton.NS do
  @moduledoc """
  RDF vocabulary namespaces for NGSI-LD.
  """

  use RDF.Vocabulary.Namespace

  # The NGSI-LD core vocabulary namespace.
  defvocab(NGSILD,
    base_iri: "https://uri.etsi.org/ngsi-ld/",
    terms: ~w(
      Property
      Relationship
      GeoProperty
      LanguageProperty
      VocabProperty
      JsonProperty
      ListProperty
      ListRelationship
      hasValue
      hasObject
      observedAt
      unitCode
      datasetId
      createdAt
      modifiedAt
      deletedAt
      instanceId
      Subscription
      Notification
      ContextSourceRegistration
      default
      hasLanguageMap
      hasVocab
      hasJSON
      hasValueList
      hasObjectList
      location
      observationSpace
      operationSpace
    ),
    strict: false
  )
end
