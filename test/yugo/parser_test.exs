defmodule Yugo.ParserTest do
  use ExUnit.Case, async: true
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

  test "parse FETCH responses" do
    [
      fetch: {123, :flags, []}
    ] = Parser.parse_response(~S|* 123 fetch (flags ())|)

    [
      fetch:
        {12, :envelope,
         %{
           bcc: [],
           cc: [{nil, "minutes@cnri.reston.va.us"}, {"John Klensin", "klensin@mit.edu"}],
           date: ~U[1996-07-16 19:23:25Z],
           from: [{"Terry Gray", "gray@cac.washington.edu"}],
           in_reply_to: nil,
           message_id: "<B27397-0100000@cac.washington.edu>",
           reply_to: [{"Terry Gray", "gray@cac.washington.edu"}],
           sender: [{"Terry Gray", "gray@cac.washington.edu"}],
           subject: "IMAP4rev1 WG mtg summary and minutes",
           to: [{nil, "imap@cac.washington.edu"}]
         }},
      fetch: {12, :flags, ["\\Seen"]}
    ] =
      Parser.parse_response(
        ~S|* 12 FETCH (FLAGS (\Seen) ENVELOPE ("Wed, 17 Jul 1996 02:23:25 -0700 (PDT)" "IMAP4rev1 WG mtg summary and minutes" (("Terry Gray" NIL "gray" "cac.washington.edu")) (("Terry Gray" NIL "gray" "cac.washington.edu")) (("Terry Gray" NIL "gray" "cac.washington.edu")) ((NIL NIL "imap" "cac.washington.edu")) ((NIL NIL "minutes" "CNRI.Reston.VA.US")("John Klensin" NIL "KLENSIN" "MIT.EDU")) NIL NIL "<B27397-0100000@cac.washington.edu>"))|
      )

    [fetch: {0, :flags, ["\\Seen", "\\Recent"]}, fetch: {0, :uid, 84}] =
      Parser.parse_response(~S|* 0 fetch (UID 84 FLags (\Seen \Recent))|)
  end

  test "parse COPYUID response" do
    [
      copyuid: %{
        validity: 38_675_294,
        source_uids: [4, 5, 6, 7, 9, 12],
        destination_uids: [304, 305, 306, 307, 309, 312]
      }
    ] =
      Parser.parse_response("* OK [COPYUID 38675294 4:7,9,12 304:307,309,312] Copy completed\r\n")

    [copyuid: %{validity: 123_456, source_uids: [1], destination_uids: [2001]}] =
      Parser.parse_response("* OK [COPYUID 123456 1 2001] Copy completed\r\n")

    result = Parser.parse_response("* OK [COPYUID 987654 1:1000 2001:3000] Copy completed\r\n")

    assert [
             copyuid: %{
               validity: 987_654,
               source_uids: source_uids,
               destination_uids: destination_uids
             }
           ] = result

    assert length(source_uids) == 1000
    assert length(destination_uids) == 1000
    assert Enum.at(source_uids, 0) == 1
    assert Enum.at(source_uids, -1) == 1000
    assert Enum.at(destination_uids, 0) == 2001
    assert Enum.at(destination_uids, -1) == 3000
  end

  test "parse LIST response" do
    [list: %{flags: [:Noselect], delimiter: "/", name: "Public Folders"}] =
      Parser.parse_response("* LIST (\Noselect) \"/\" \"Public Folders\"\r\n")

    [list: %{flags: [:Unmarked, :HasNoChildren], delimiter: "/", name: "INBOX"}] =
      Parser.parse_response("* LIST (\Unmarked \HasNoChildren) \"/\" \"INBOX\"\r\n")

    [list: %{flags: [:Unmarked, :HasNoChildren], delimiter: "/", name: "Drafts"}] =
      Parser.parse_response("* LIST (\Unmarked \HasNoChildren) \"/\" \"Drafts\"\r\n")
  end
end
