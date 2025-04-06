defmodule IbExExamplesTest do
  use ExUnit.Case
  doctest IbExExamples

  test "greets the world" do
    assert IbExExamples.hello() == :world
  end
end
