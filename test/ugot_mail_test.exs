defmodule UgotMailTest do
  use ExUnit.Case
  doctest UgotMail

  test "greets the world" do
    assert UgotMail.hello() == :world
  end
end
