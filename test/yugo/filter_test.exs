defmodule Yugo.FilterTest do
  use ExUnit.Case
  alias Yugo.Filter
  doctest Yugo.Filter

  test "rejects flags that are has_flag AND lacks_flag" do
    assert_raise RuntimeError,
                 "Cannot enforce a has_flag constraint for \":seen\" because this filter already has a lacks_flag constraint for the same flag.",
                 fn ->
                   Filter.all()
                   |> Filter.has_flag(:flagged)
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
    %Filter{has_flags: [:draft, :seen]} =
      Filter.all()
      |> Filter.has_flag(:seen)
      |> Filter.has_flag(:draft)
      |> Filter.has_flag(:seen)

    %Filter{lacks_flags: [:draft]} =
      Filter.all()
      |> Filter.lacks_flag(:draft)
      |> Filter.lacks_flag(:draft)
      |> Filter.lacks_flag(:draft)
  end

  test "filters on subject_matches" do
    f =
      Filter.all()
      |> Filter.subject_matches(~r/(hello|goodbye)/)

    assert not Filter.accepts?(f, %{envelope: %{subject: nil}})
    assert not Filter.accepts?(f, %{envelope: %{subject: ""}})
    assert Filter.accepts?(f, %{envelope: %{subject: "this subject has 'hello' in it"}})
    assert Filter.accepts?(f, %{envelope: %{subject: "goodgoodbye"}})
  end

  test "filters on flags" do
    has_seen_flag =
      Filter.all()
      |> Filter.has_flag(:seen)

    assert not Filter.accepts?(has_seen_flag, %{flags: []})
    assert Filter.accepts?(has_seen_flag, %{flags: [:seen]})
    assert Filter.accepts?(has_seen_flag, %{flags: [:recent, :seen, :draft]})

    has_seen_lacks_draft =
      has_seen_flag
      |> Filter.lacks_flag(:draft)

    assert not Filter.accepts?(has_seen_lacks_draft, %{flags: [:draft]})
    assert not Filter.accepts?(has_seen_lacks_draft, %{flags: [:seen, :draft]})
    assert Filter.accepts?(has_seen_lacks_draft, %{flags: [:seen, :deleted]})
  end

  test "filters on sender" do
    f =
      Filter.all()
      |> Filter.sender_matches(~r/bob/)

    assert not Filter.accepts?(f, %{envelope: %{sender: []}})
    assert not Filter.accepts?(f, %{envelope: %{sender: ["foo@bar.com", "baz@biz.com"]}})
    assert Filter.accepts?(f, %{envelope: %{sender: ["foo@bar.com", "bob@example.com"]}})
    assert Filter.accepts?(f, %{envelope: %{sender: ["zzz@foo.bob"]}})
  end
end
