defmodule GetmailTest do
  use ExUnit.Case
  doctest Getmail

  test "greets the world" do
    assert Getmail.hello() == :world
  end
end
