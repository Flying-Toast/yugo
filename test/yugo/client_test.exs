defmodule Yugo.ClientTest do
  use ExUnit.Case, asnc: true
  doctest Yugo.Client
  import Helpers.Client

  test "Upgrades insecure connections via STARTTLS" do
    accept_gen_tcp()
    |> do_hello()
    |> do_starttls()
    |> do_select_bootstrap(1)
  end

  test "cancels IDLE" do
    ssl_server()
    |> assert_comms(~S"""
    S: * 2 EXISTS
    C: DONE
    """)
  end

  test "receives one-body text/plain message" do
    ssl_server()
    |> assert_comms(~S"""
    S: * 2 EXISTS
    C: DONE
    S: 4 OK idle done
    C: 5 FETCH 2 (BODY FLAGS ENVELOPE)
    S: * 2 FETCH (FLAGS () BODY ("text" "plain" ("charset" "us-ascii" "format" "flowed") NIL NIL "7bit" 47 6) ENVELOPE ("Wed, 07 Dec 2022 18:02:41 -0500" "Hello! (subject)" (("Marge Simpson" NIL "marge" "simpsons-family.com")) (("Marge Simpson" NIL "marge" "simpsons-family.com")) (("Marge" NIL "marge" "simpsons-family.com")) (("HOMIEEEE" NIL "homer" "simpsons-family.com")) NIL NIL NIL "fjaelwkjfi oaf<$ ))) \""))
    S: 5 oK done
    C: 6 FETCH 2 (BODY.PEEK[1])
    S: * 2 fetcH (BODY[1] {47}
    Hello!

    this is the message text.
    Bye!


    )
    S: 6 ok fetched
    """)

    receive do
      {:email, _client, msg} ->
        assert msg ==
                 %{
                   bcc: [],
                   bodies: [
                     [
                       {"text/plain",
                        "Hello!\r\n\r\nthis is the message text.\r\nBye!\r\n\r\n\r\n"}
                     ]
                   ],
                   cc: [],
                   date: ~U[2022-12-07 13:02:41Z],
                   flags: [],
                   in_reply_to: nil,
                   message_id: "fjaelwkjfi oaf<$ ))) \"",
                   reply_to: ["marge@simpsons-family.com"],
                   sender: ["marge@simpsons-family.com"],
                   subject: "Hello! (subject)",
                   to: ["homer@simpsons-family.com"]
                 }
    end
  end
end
