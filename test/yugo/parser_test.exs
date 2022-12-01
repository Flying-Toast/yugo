defmodule Yugo.ParserTest do
  use ExUnit.Case
  alias Yugo.Parser
  doctest Yugo.Parser

  test "tagged responses" do
    [tagged_response: {123, :ok, "CAPABILITY completed"}] =
      Parser.parse_response("123 OK CAPABILITY completed\r\n")
  end

  test "parse capabilities" do
    [
      capabilities: [
        "IMAP4REV1",
        "SASL-IR",
        "LOGIN-REFERRALS",
        "ID",
        "ENABLE",
        "IDLE",
        "LITERAL+",
        "AUTH=PLAIN"
      ]
    ] =
      Parser.parse_response(
        "* CAPABILITY IMAP4rev1 SASL-IR LOGIN-REFERRALS ID ENABLE IDLE LITERAL+ AUTH=PLAIN\r\n"
      )

    [capabilities: []] = Parser.parse_response("* capability         \r\n")
  end

  test "parse command continuation request" do
    [:continuation] = Parser.parse_response("+ continue...\r\n")
    [:continuation] = Parser.parse_response("+ \r\n")
  end

  test "parse untagged SELECT responses" do
    [permanent_flags: ["\\DELETED", "\\SEEN", "\\*"]] =
      Parser.parse_response("* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited\r\n")

    [permanent_flags: []] =
      Parser.parse_response("* OK [PERMANENTFLAGS ()] No permanent flags permitted\r\n")

    [first_unseen: 12] = Parser.parse_response("* OK [UNSEEN 12] Message 12 is first unseen\r\n")

    [uid_validity: 3_857_529_045] =
      Parser.parse_response("* OK [UIDVALIDITY 3857529045] UIDs valid\r\n")

    [uid_next: 4392] = Parser.parse_response("* OK [UIDNEXT 4392] Predicted next UID\r\n")

    [applicable_flags: ["\\ANSWERED", "\\FLAGGED", "\\DELETED", "\\SEEN", "\\DRAFT"]] =
      Parser.parse_response("* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n")

    [applicable_flags: []] = Parser.parse_response("* FLAGS () nope no flags\r\n")
  end
end
