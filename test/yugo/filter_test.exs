defmodule Yugo.FilterTest do
  use ExUnit.Case
  alias Yugo.Filter
  doctest Yugo.Filter

  test "rejects flags that are has_flag AND lacks_flag" do
    assert_raise RuntimeError,
                 "Cannot enforce a has_flag constraint for \":seen\" because this filter already has a lacks_flag constraint for the same flag.",
                 fn ->
                   Filter.all()
                   |> Filter.has_flag(:recent)
                   |> Filter.lacks_flag(:draft)
                   |> Filter.lacks_flag(:seen)
                   |> Filter.has_flag(:seen)
                 end

    assert_raise RuntimeError,
                 "Cannot enforce a lacks_flag constraint for \":seen\" because this filter already has a has_flag constraint for the same flag.",
                 fn ->
                   Filter.all()
                   |> Filter.has_flag(:seen)
                   |> Filter.lacks_flag(:seen)
                 end
  end

  test "doesn't add duplicate flag constraints" do
    %Filter{has_flags: [:recent, :seen]} =
      Filter.all()
      |> Filter.has_flag(:seen)
      |> Filter.has_flag(:recent)
      |> Filter.has_flag(:seen)

    %Filter{lacks_flags: ["myflag"]} =
      Filter.all()
      |> Filter.lacks_flag("myflag")
      |> Filter.lacks_flag("myflag")
      |> Filter.lacks_flag("myflag")
  end
end
