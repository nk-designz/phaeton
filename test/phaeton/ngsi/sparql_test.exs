defmodule Phaeton.NGSI.SparqlTest do
  use ExUnit.Case, async: true

  alias Phaeton.NGSI.Sparql

  test "connected entity types example constrains source and target to IRIs" do
    example = Enum.find(Sparql.example_queries(), &(&1.name == "Connected entity types"))

    assert example
    assert example.query =~ "FILTER(isIRI(?source))"
    assert example.query =~ "FILTER(isIRI(?target))"
  end
end
