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

  test "parse PERMANENTFLAGS" do
    [permanent_flags: ["\\DELETED", "\\SEEN", "\\*"]] =
      Parser.parse_response("* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited\r\n")

    [permanent_flags: []] =
      Parser.parse_response("* OK [PERMANENTFLAGS ()] No permanent flags permitted\r\n")
  end
end
