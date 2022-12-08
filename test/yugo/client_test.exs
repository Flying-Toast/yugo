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

  test "email with a text attachment" do
    ssl_server()
    |> assert_comms(~S"""
    S: * 2 EXISTS
    C: DONE
    S: 4 OK idle done
    C: 5 FETCH 2 (BODY FLAGS ENVELOPE)
    S: * 2 FETCH (FLAGS (\Recent) BODY (("text" "plain" ("charset" "us-ascii" "format" "flowed") NIL NIL "7bit" 34 4)("text" "x-elixir" ("charset" "us-ascii") NIL NIL "base64" 78 1) "mixed") ENVELOPE ("Wed, 07 Dec 2022 23:21:35 -0500" "Foo Bar Baz Buzz Biz Boz" (("Bob Jones" NIL "bobjones" "example.org")) (("Bob Jones" NIL "bobjones" "example.org")) (("Bob Jones" NIL "bobjones" "example.org")) ((NIL NIL "foo" "bar.com")) NIL NIL NIL "Fjaewlk jflkewajf i3ajf0943aF $#AF $#FA#$ F#AF {123}"))
    S: 5 oK done
    C: 6 FETCH 2 (BODY.PEEK[1] BODY.PEEK[2])
    S: * 2 FETCH (BODY[1] {62}
    Hello!

    See the attached file for an Elixir hello world.

     BODY[2] "ZGVmbW9kdWxlIEhlbGxvIGRvCiAgZGVmIGdyZWV0IGRvCiAgICA6d29ybGQKICBlbmQKZW5kCg==")
    S: 6 ok .
    """)

    receive do
      {:email, _client, msg} ->
        assert msg ==
                 %{
                   bcc: [],
                   bodies: [
                     [
                       {"text/plain",
                        "Hello!\r\n\r\nSee the attached file for an Elixir hello world.\r\n\r\n"}
                     ],
                     [
                       {"text/x-elixir",
                        "defmodule Hello do\n  def greet do\n    :world\n  end\nend\n"}
                     ]
                   ],
                   cc: [],
                   date: ~U[2022-12-07 18:21:35Z],
                   flags: [],
                   in_reply_to: nil,
                   message_id: "Fjaewlk jflkewajf i3ajf0943aF $#AF $#FA#$ F#AF {123}",
                   reply_to: ["bobjones@example.org"],
                   sender: ["bobjones@example.org"],
                   subject: "Foo Bar Baz Buzz Biz Boz",
                   to: ["foo@bar.com"]
                 }
    end
  end

  test "multiple sender addresses" do
    ssl_server()
    |> assert_comms(~S"""
    S: * 2 EXISTS
    C: DONE
    S: 4 OK idle done
    C: 5 FETCH 2 (BODY FLAGS ENVELOPE)
    S: * 2 FETCH (FLAGS () BODY ("text" "plain" ("charset" "us-ascii" "format" "flowed") NIL NIL "7bit" 5 1) ENVELOPE ("Wed, 07 Dec 2022 18:02:41 -0500" "Hello! (subject)" (("Marge Simpson" NIL "marge" "simpsons-family.com")) (("Marge Simpson" NIL "marge" "simpsons-family.com")(NIL NIL "bob" "bobs-email.com")) (("Marge" NIL "marge" "simpsons-family.com")) (("HOMIEEEE" NIL "homer" "simpsons-family.com")) ((NIL NIL "foo" "bar.com")("barfoo" NIL "bar" "foo.com")({0}
    NIL "fizz" "buzz.com")) NIL "123 abc 456" {0}
    ))
    S: 5 oK done
    C: 6 FETCH 2 (BODY.PEEK[1])
    S: * 2 fetcH (BODY[1] "hello")
    S: 6 ok fetched
    """)

    receive do
      {:email, _client, msg} ->
        assert msg ==
                 %{
                   bcc: [],
                   bodies: [
                     [
                       {"text/plain", "hello"}
                     ]
                   ],
                   cc: ["foo@bar.com", "bar@foo.com", "fizz@buzz.com"],
                   date: ~U[2022-12-07 13:02:41Z],
                   flags: [],
                   in_reply_to: "123 abc 456",
                   message_id: "",
                   reply_to: ["marge@simpsons-family.com"],
                   sender: ["marge@simpsons-family.com", "bob@bobs-email.com"],
                   subject: "Hello! (subject)",
                   to: ["homer@simpsons-family.com"]
                 }
    end
  end
end
