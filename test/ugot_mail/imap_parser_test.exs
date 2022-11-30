defmodule UgotMailTest do
  use ExUnit.Case
  alias UgotMail.IMAPParser, as: Parser
  doctest UgotMail.IMAPParser

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
  end
end
