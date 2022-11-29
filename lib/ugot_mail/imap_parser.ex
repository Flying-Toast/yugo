defmodule UgotMail.IMAPParser do
  import NimbleParsec

  IO.puts("TODO: all string()s should be case insensitive!!!!")

  sp = ascii_char([?\s])
  spig = ignore(sp)

  crlf = ignore(string("\r\n"))

  char = ascii_char([0x01..0x7F])

  ctl = ascii_char([0x00..0x1F, 0x7F])

  list_wildcards = ascii_char([?%, ?*])

  quoted_specials = ascii_char([?", ?\n])

  resp_specials = ascii_char([?]])

  atom_specials =
    choice([
      ascii_char([?(, ?), ?{, ?\s]),
      ctl,
      list_wildcards,
      quoted_specials
    ])

  atom_char =
    lookahead_not(atom_specials)
    |> concat(char)

  astring_char = choice([atom_char, resp_specials])

  tag =
    lookahead_not(ascii_char([?+]))
    |> concat(astring_char)
    |> times(min: 1)
    |> reduce(:to_string)

  text_char =
    lookahead_not(ascii_char([?\r, ?\n]))
    |> concat(char)

  utf8_tail = ascii_char([0x80, 0xBF])

  utf8_2 =
    ascii_char([0xC2..0xDF])
    |> concat(utf8_tail)

  utf8_3 =
    choice([
      ascii_char([0xE0])
      |> ascii_char([0xA0..0xBF])
      |> concat(utf8_tail),
      ascii_char([0xE1..0xEC])
      |> times(utf8_tail, 2),
      ascii_char([0xED])
      |> ascii_char([0x80..0x9F])
      |> concat(utf8_tail),
      ascii_char([0xEE..0xEF])
      |> times(utf8_tail, 2)
    ])

  utf8_4 =
    choice([
      ascii_char([0xF0])
      |> ascii_char([0x90..0xBF])
      |> times(utf8_tail, 2),
      ascii_char([0xF1..0xF3])
      |> times(utf8_tail, 3),
      ascii_char([0xF4])
      |> ascii_char([0x80..0x8F])
      |> times(utf8_tail, 2)
    ])

  text =
    choice([
      text_char,
      utf8_2,
      utf8_3,
      utf8_4
    ])
    |> times(min: 1)

  atom = times(atom_char, min: 1)

  quoted_char =
    choice([
      lookahead_not(quoted_specials)
      |> concat(text_char),
      ascii_char([?\\])
      |> concat(quoted_specials),
      utf8_2,
      utf8_3,
      utf8_4
    ])

  quoted =
    ascii_char([?"])
    |> repeat(quoted_char)
    |> ascii_char([?"])

  charset = choice([atom, quoted])

  auth_type = atom

  capability =
    choice([
      atom,
      string("AUTH=")
      |> concat(auth_type)
    ])

  capability_data =
    string("CAPABILITY")
    |> repeat(sp |> concat(capability))
    |> concat(sp)
    |> string("IMAP4rev2")
    |> repeat(sp |> concat(capability))

  nz_number = integer(min: 1)
  nz_number64 = nz_number

  uniqueid = nz_number
  append_uid = uniqueid

  resp_code_apnd =
    string("APPENDUID ")
    |> concat(nz_number)
    |> concat(sp)
    |> concat(append_uid)

  uid_range =
    uniqueid
    |> ascii_char([?:])
    |> concat(uniqueid)

  base_uid_set = choice([uniqueid, uid_range])

  comma_then_base_uid_set =
    ascii_char([?,])
    |> concat(base_uid_set)

  uid_set =
    base_uid_set
    |> repeat(comma_then_base_uid_set)

  resp_code_copy =
    string("COPYUID ")
    |> concat(nz_number)
    |> concat(sp)
    |> concat(uid_set)
    |> concat(sp)
    |> concat(uid_set)

  flag_keyword =
    choice(Enum.map(~w[$MDNSent $Forwarded $Junk $NotJunk $Phishing], &string/1) ++ [atom])

  flag_extension =
    ascii_char([?\\])
    |> concat(atom)

  flag =
    choice(
      Enum.map(~W[\Answered \Flagged \Deleted \Seen \Draft], &string/1) ++
        [flag_keyword, flag_extension]
    )

  flag_perm = choice([flag, string("\\*")])

  resp_text_code =
    choice(
      Enum.map(
        ~w[ALERT PARSE READ-ONLY READ-WRITE TRYCREATE UIDNOTSTICKY AUTHENTICATIONFAILED UNAVAILABLE AUTHORIZATIONFAILED EXPIRED PRIVACYREQUIRED CONTACTADMIN NOPERM INUSE EXPUNGEISSUED CORRUPTION SERVERBUG CLIENTBUG CANNOT LIMIT OVERQUOTA ALREADYEXISTS NONEXISTENT NOTSAVED HASCHILDREN CLOSED UNKNOWN-CTE],
        &string/1
      ) ++
        [
          string("BADCHARSET")
          |> (string(" (")
              |> concat(charset)
              |> repeat(concat(sp, charset))
              |> ascii_char([?)])
              |> optional()),
          capability_data,
          resp_code_apnd,
          resp_code_copy,
          string("UIDNEXT ")
          |> concat(nz_number),
          string("UIDVALIDITY ")
          |> concat(nz_number),
          atom
          |> optional(
            sp
            |> (lookahead_not(ascii_char([?]]))
                |> concat(text_char)
                |> times(min: 1))
          ),
          string("PERMANENTFLAGS (")
          |> optional(
            flag_perm
            |> repeat(
              sp
              |> concat(flag_perm)
            )
          )
          |> ascii_char([?)])
        ]
    )

  resp_text =
    ascii_char([?[])
    |> concat(resp_text_code)
    |> ascii_char([?]])
    |> concat(sp)
    |> optional()
    |> optional(text)
    |> reduce(:to_string)

  resp_cond_state =
    choice([
      string("OK"),
      string("NO"),
      string("BAD")
    ])
    |> concat(spig)
    |> concat(resp_text)

  response_tagged =
    tag
    |> concat(spig)
    |> concat(resp_cond_state)
    |> concat(crlf)
end
