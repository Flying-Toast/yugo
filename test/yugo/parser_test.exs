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

  test "parse FETCH response with simple RFC822.HEADER" do
    [
      fetch: {1, :rfc822_header, "From: example@example.com\r\nSubject: Test Email\r\n\r\n"}
    ] =
      Parser.parse_response(
        "* 1 FETCH (RFC822.HEADER \"From: example@example.com\r\nSubject: Test Email\r\n\r\n\")"
      )

  end

  test "parse FETCH response with complex RFC822.HEADER" do
    headers1 = "From: example@example.com\r\n" <>
              "X-Spam-Checker-Version: SpamAssassin 3.4.6 (2021-04-09)\r\n" <>
              "X-Spam-Level:\r\n" <>
              "X-Spam-Pyzor:\r\n" <>
              "X-Spam-Status: No, score=-100.0 required=6.0 shortcircuit=ham
	autolearn=disabled version=3.4.6\r\n" <>
              "Subject: Multi-Line Subject\r\n\t Continued Here\r\n" <>
              "To: recipient1@example.com,\r\n recipient2@example.com\r\n" <>
              "CC: cc@example.com\r\nBCC: bcc@example.com\r\n\r\n"
    [
      fetch: {2, :rfc822_header, headers2}
    ] =
      Parser.parse_response(
        "* 2 FETCH (RFC822.HEADER \"#{headers1}\")"
      )

    assert headers1 == headers2

  end
end
