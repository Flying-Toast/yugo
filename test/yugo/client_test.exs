defmodule Yugo.ClientTest do
  use ExUnit.Case, async: false
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
    S: * 2 FETCH (FLAGS (\sEEn) BODY ("text" "plain" ("charset" "us-ascii" "format" "flowed") NIL NIL "7bit" 47 6) ENVELOPE ("Wed, 07 Dec 2022 18:02:41 -0500" NIL (("Marge Simpson" NIL "marge" "simpsons-family.com")) (("Marge Simpson" NIL "marge" "simpsons-family.com")) (("Marge" NIL "marge" "simpsons-family.com")) (("HOMIEEEE" NIL "homer" "simpsons-family.com")) NIL NIL NIL "fjaelwkjfi oaf<$ ))) \""))
    S: 5 oK done
    C: 6 FETCH 2 (BODY.PEEK[1])
    S: * 2 fetcH (BODY[1] {14}
    Hello 123
    456)
    S: 6 ok fetched
    """)

    receive do
      {:email, _client, msg} ->
        assert msg ==
                 %Yugo.Message{
                   bcc: [],
                   body:
                     {"text/plain", %{"charset" => "us-ascii", "format" => "flowed"},
                      "Hello 123\r\n456"},
                   cc: [],
                   date: ~U[2022-12-07 13:02:41Z],
                   flags: [:seen],
                   in_reply_to: nil,
                   message_id: "fjaelwkjfi oaf<$ ))) \"",
                   reply_to: [{"Marge", "marge@simpsons-family.com"}],
                   sender: [{"Marge Simpson", "marge@simpsons-family.com"}],
                   subject: nil,
                   to: [{"HOMIEEEE", "homer@simpsons-family.com"}],
                   from: [{"Marge Simpson", "marge@simpsons-family.com"}]
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
                 %Yugo.Message{
                   bcc: [],
                   body: [
                     {"text/plain", %{"charset" => "us-ascii", "format" => "flowed"},
                      "Hello!\r\n\r\nSee the attached file for an Elixir hello world.\r\n\r\n"},
                     {"text/x-elixir", %{"charset" => "us-ascii"},
                      "defmodule Hello do\n  def greet do\n    :world\n  end\nend\n"}
                   ],
                   cc: [],
                   date: ~U[2022-12-07 18:21:35Z],
                   flags: [],
                   in_reply_to: nil,
                   message_id: "Fjaewlk jflkewajf i3ajf0943aF $#AF $#FA#$ F#AF {123}",
                   reply_to: [{"Bob Jones", "bobjones@example.org"}],
                   sender: [{"Bob Jones", "bobjones@example.org"}],
                   subject: "Foo Bar Baz Buzz Biz Boz",
                   to: [{nil, "foo@bar.com"}],
                   from: [{"Bob Jones", "bobjones@example.org"}]
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
    S: * 2 FETCH (FLAGS () BODY ("text" "plain" () NIL NIL "7bit" 5 1) ENVELOPE ("Wed, 07 Dec 2022 18:02:41 -0500" "Hello! (subject)" (("Marge Simpson" NIL "marge" "simpsons-family.com")) (("Marge Simpson" NIL "marge" "simpsons-family.com")(NIL NIL "bob" "bobs-email.com")) (("Marge" NIL "marge" "simpsons-family.com")) (("HOMIEEEE" NIL "homer" "simpsons-family.com")) ((NIL NIL "foo" "bar.com")("barfoo" NIL "bar" "foo.com")({0}
    S: NIL "fizz" "buzz.com")) NIL "123 abc 456" {0}
    S: ))
    S: 5 oK done
    C: 6 FETCH 2 (BODY.PEEK[1])
    S: * 2 fetcH (BODY[1] "hello")
    S: 6 ok fetched
    """)

    receive do
      {:email, _client, msg} ->
        assert msg ==
                 %Yugo.Message{
                   bcc: [],
                   body: {"text/plain", %{}, "hello"},
                   cc: [{nil, "foo@bar.com"}, {"barfoo", "bar@foo.com"}, {"", "fizz@buzz.com"}],
                   date: ~U[2022-12-07 13:02:41Z],
                   flags: [],
                   in_reply_to: "123 abc 456",
                   message_id: "",
                   reply_to: [{"Marge", "marge@simpsons-family.com"}],
                   sender: [
                     {"Marge Simpson", "marge@simpsons-family.com"},
                     {nil, "bob@bobs-email.com"}
                   ],
                   subject: "Hello! (subject)",
                   to: [{"HOMIEEEE", "homer@simpsons-family.com"}],
                   from: [{"Marge Simpson", "marge@simpsons-family.com"}]
                 }
    end
  end

  test "html body" do
    ssl_server()
    |> assert_comms(~S"""
    S: * 2 exists
    C: DONE
    S: 4 ok * * * ok ok ok ok
    C: 5 FETCH 2 (BODY FLAGS ENVELOPE)
    S: * 2 FETCH (FLAGS (\Recent) BODY (("text" "plain" ("charset" "us-ascii") NIL NIL "7bit" 42 4)("text" "html" ("charset" "us-ascii") NIL NIL "7bit" 206 0) "alternative") ENVELOPE ("Thu, 08 Dec 2022 09:59:48 -0500" "An HTML email" (("Aych T. Emmel" NIL "person" "domain.com")) ((NIL NIL "person" "domain.com")) ((NIL NIL "foo" "bar.com")) ((NIL NIL "bar" "foo.com")) NIL NIL NIL "<><><><><>"))
    S: 5 OK Fetch completed (0.001 + 0.000 secs).
    C: 6 FETCH 2 (BODY.PEEK[1] BODY.PEEK[2])
    S: * 2 FETCH (BODY[1] {42}
    _Wow!!_

    This *email* has rich text!

     BODY[2] {206}
    <div id="geary-body" dir="auto"><u><font size="1">Wow!!</font></u><div><br></div><div>This <b>email</b>&nbsp;has <font face="monospace" color="#f5c211">rich text</font><font face="sans">!</font></div></div>)
    6 OK Fetch completed (0.001 + 0.000 secs).
    S: 6 OK done fetching
    C: 7 IDLE
    """)

    receive do
      {:email, _client, msg} ->
        assert msg == %Yugo.Message{
                 bcc: [],
                 body: [
                   {"text/plain", %{"charset" => "us-ascii"},
                    "_Wow!!_\r\n\r\nThis *email* has rich text!\r\n\r\n"},
                   {"text/html", %{"charset" => "us-ascii"},
                    "<div id=\"geary-body\" dir=\"auto\"><u><font size=\"1\">Wow!!</font></u><div><br></div><div>This <b>email</b>&nbsp;has <font face=\"monospace\" color=\"#f5c211\">rich text</font><font face=\"sans\">!</font></div></div>"}
                 ],
                 cc: [],
                 date: ~U[2022-12-08 04:59:48Z],
                 flags: [],
                 in_reply_to: nil,
                 message_id: "<><><><><>",
                 reply_to: [{nil, "foo@bar.com"}],
                 sender: [{nil, "person@domain.com"}],
                 subject: "An HTML email",
                 to: [{nil, "bar@foo.com"}],
                 from: [{"Aych T. Emmel", "person@domain.com"}]
               }
    end
  end

  test "nested multipart body" do
    onepart = ~S|("x-foo" "x-bar" nil nil nil "7bit" 10)|
    mpart1 = ~s|(#{onepart}#{onepart} "alternative")|
    mpart = ~s|(#{onepart}#{onepart}#{mpart1} "alternative")|
    body_structure = ~s|(#{mpart}#{mpart1}#{onepart} "alternative")|

    ssl_server()
    |> assert_comms(~s"""
    S: * 2 exists
    C: DONE
    S: 4 ok * * * ok ok ok ok
    C: 5 FETCH 2 (BODY FLAGS ENVELOPE)
    S: * 2 FETCH (uid 123 FLAGS () BODY #{body_structure} ENVELOPE ("Wed, 07 Dec 2022 18:02:41 -0500" NIL (("Marge Simpson" NIL "marge" "simpsons-family.com")) (("Marge Simpson" NIL "marge" "simpsons-family.com")) (("Marge" NIL "marge" "simpsons-family.com")) (("HOMIEEEE" NIL "homer" "simpsons-family.com")) NIL NIL nil niL))
    S: 5 OK OK OK
    C: 6 FETCH 2 (BODY.PEEK[1.1] BODY.PEEK[1.2] BODY.PEEK[1.3.1] BODY.PEEK[1.3.2] BODY.PEEK[2.1] BODY.PEEK[2.2] BODY.PEEK[3])
    S: * 2 fetch (BODY[1.1] "this is 1.1" BODY[1.2] "this is 1.2" BODY[1.3.1] "this is 1.3.1" body[1.3.2] "this is 1.3.2" body[2.1] "this is 2.1" body[2.2] "this is 2.2" body[3] "this is 3")
    S: 6 ok fetchified
    C: 7 IDLE
    """)

    receive do
      {:email, _client, msg} ->
        assert msg ==
                 %Yugo.Message{
                   bcc: [],
                   body: [
                     [
                       {"x-foo/x-bar", %{}, "this is 1.1"},
                       {"x-foo/x-bar", %{}, "this is 1.2"},
                       [
                         {"x-foo/x-bar", %{}, "this is 1.3.1"},
                         {"x-foo/x-bar", %{}, "this is 1.3.2"}
                       ]
                     ],
                     [
                       {"x-foo/x-bar", %{}, "this is 2.1"},
                       {"x-foo/x-bar", %{}, "this is 2.2"}
                     ],
                     {"x-foo/x-bar", %{}, "this is 3"}
                   ],
                   cc: [],
                   date: ~U[2022-12-07 13:02:41Z],
                   flags: [],
                   in_reply_to: nil,
                   message_id: nil,
                   reply_to: [{"Marge", "marge@simpsons-family.com"}],
                   sender: [{"Marge Simpson", "marge@simpsons-family.com"}],
                   subject: nil,
                   to: [{"HOMIEEEE", "homer@simpsons-family.com"}],
                   from: [{"Marge Simpson", "marge@simpsons-family.com"}]
                 }
    end
  end
end
