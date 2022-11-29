defmodule UgotMail.IMAPParser do
  import NimbleParsec

  IO.puts("TODO: all string()s should be case insensitive!!!!")

  sp = ascii_char([?\s])
  spig = ignore(sp)

  nil_ =
    string("NIL")
    |> replace(nil)

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
    #|> concat(sp)
    #|> string("IMAP4rev2")
    #|> repeat(sp |> concat(capability))

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
      string("OK") |> replace(:ok),
      string("NO") |> replace(:no),
      string("BAD") |> replace(:bad)
    ])
    |> concat(spig)
    |> concat(resp_text)

  response_tagged =
    tag
    |> concat(spig)
    |> concat(resp_cond_state)
    |> concat(crlf)

  alpha = ascii_char([?A..?Z, ?a..?z])
  digit = ascii_char([?0..?9])

  base64_char =
    choice([
      alpha,
      digit,
      ascii_char([?+, ?/])
    ])

  base64_terminal =
    choice([
      times(base64_char, 2)
      |> string("=="),
      times(base64_char, 3)
      |> ascii_char([?=])
    ])

  base64 =
    times(base64_char, 4)
    |> repeat()
    |> optional(base64_terminal)

  continue_req =
    ascii_char([?+])
    |> choice([resp_text, base64])
    |> concat(crlf)

  resp_cond_bye =
    string("BYE ")
    |> concat(resp_text)

  flag_list =
    ascii_char([?(])
    |> optional(
      flag
      |> repeat(sp |> concat(flag))
    )
    |> ascii_char([?)])

  child_mbox_flag = choice([string("\\HasChildren"), string("\\HasNoChildren")])

  mbx_list_oflag =
    choice([
      string("\\Noinferiors"),
      string("\\Subscribed"),
      string("\\Remote"),
      child_mbox_flag,
      flag_extension
    ])

  mbx_list_sflag = choice(Enum.map(~W[\NonExistent \Noselect \Marked \Unmarked], &string/1))

  mbx_list_flags =
    choice([
      repeat(mbx_list_oflag |> concat(sp))
      |> concat(mbx_list_sflag)
      |> repeat(sp |> concat(mbx_list_oflag)),
      mbx_list_oflag
      |> repeat(sp |> concat(mbx_list_oflag))
    ])

  char8 = ascii_char([0x01..0xFF])

  number = integer(min: 1)
  number64 = number

  defp n_literal_octets(
         rest,
         [num_octets | acc],
         context,
         line,
         offset
       ) do
    <<octets::binary-size(num_octets), rest::binary>> = rest
    {rest, [octets | acc], context}
  end

  literal =
    ignore(ascii_char([?{]))
    |> concat(number64)
    |> ignore(ascii_char([?}]))
    |> concat(crlf)
    |> post_traverse({:n_literal_octets, []})

  literal8 = ignore(ascii_char([?~])) |> concat(literal)

  string_ = choice([quoted, literal])

  astring =
    choice([
      astring_char
      |> times(min: 1),
      string_
    ])

  mailbox = choice([string("INBOX"), astring])

  mbox_list_extended_item_tag = astring

  seq_number = choice([nz_number, ascii_char([?*])])

  seq_range =
    seq_number
    |> ascii_char([?:])
    |> concat(seq_number)

  seq_last_command = ascii_char([?$])

  sequence_set_rept_base = choice([seq_number, seq_range])

  sequence_set =
    choice([
      seq_last_command,
      sequence_set_rept_base
      |> repeat(
        ascii_char([?,])
        |> concat(sequence_set_rept_base)
      )
      |> concat(seq_last_command)
    ])

  tagged_ext_simple =
    choice([
      sequence_set,
      number,
      number64
    ])

  defcombinatorp(
    :tagged_ext_comp,
    choice([
      astring,
      ascii_char([?(])
      |> parsec(:tagged_ext_comp)
      |> ascii_char([?)]),
      parsec(:tagged_ext_comp)
      |> repeat(sp |> parsec(:tagged_ext_comp))
    ])
  )

  tagged_ext_val =
    choice([
      tagged_ext_simple,
      ascii_char([?(])
      |> optional(parsec(:tagged_ext_comp))
      |> ascii_char([?)])
    ])

  mbox_list_extended_item =
    mbox_list_extended_item_tag
    |> concat(sp)
    |> concat(tagged_ext_val)

  mbox_list_extended =
    ascii_char([?(])
    |> optional(
      mbox_list_extended_item
      |> repeat(sp |> concat(mbox_list_extended_item))
    )
    |> ascii_char([?)])

  mailbox_list =
    ascii_char([?(])
    |> optional(mbx_list_flags)
    |> string(") ")
    |> choice([
      ascii_char([?"])
      |> concat(quoted_char)
      |> ascii_char([?"]),
      nil_
    ])
    |> concat(sp)
    |> concat(mailbox)
    |> optional(sp |> concat(mbox_list_extended))

  tag_string = astring

  search_correlator =
    string(" (TAG ")
    |> concat(tag_string)
    |> ascii_char([?)])

  tagged_label_fchar = choice([alpha, ascii_char([?-, ?_, ?.])])

  tagged_label_char = choice([tagged_label_fchar, digit, ascii_char([?:])])

  tagged_ext_label =
    tagged_label_fchar
    |> repeat(tagged_label_char)

  search_modifier_name = tagged_ext_label

  search_return_value = tagged_ext_val

  search_ret_data_ext =
    search_modifier_name
    |> concat(sp)
    |> concat(search_return_value)

  search_return_data =
    choice([
      search_ret_data_ext,
      string("COUNT ") |> concat(number),
      string("ALL ") |> concat(sequence_set),
      string("MAX ") |> concat(nz_number),
      string("MIN ") |> concat(nz_number)
    ])

  esearch_response =
    string("ESEARCH")
    |> optional(search_correlator)
    |> string(" UID")
    |> repeat(sp |> concat(search_return_data))

  status_att_val =
    choice([
      string("MESSAGES ") |> concat(number),
      string("UIDNEXT ") |> concat(nz_number),
      string("UIDVALIDITY ") |> concat(nz_number),
      string("UNSEEN ") |> concat(number),
      string("DELETED ") |> concat(number),
      string("SIZE ") |> concat(number64)
    ])

  status_att_list =
    status_att_val
    |> repeat(sp |> concat(status_att_val))

  namespace_response_extension =
    sp
    |> concat(string_)
    |> string(" (")
    |> concat(string_)
    |> repeat(sp |> concat(string_))
    |> ascii_char([?)])

  namespace_response_extensions = repeat(namespace_response_extension)

  namespace_descr =
    ascii_char([?(])
    |> concat(string_)
    |> concat(sp)
    |> choice([
      nil_,
      ascii_char([?"])
      |> concat(quoted_char)
      |> ascii_char([?"])
    ])
    |> optional(namespace_response_extensions)

  ascii_char([?)])

  namespace =
    choice([
      nil_,
      ascii_char([?(])
      |> times(namespace_descr, min: 1)
      |> ascii_char([?)])
    ])

  namespace_response =
    string("NAMESPACE ")
    |> concat(namespace)
    |> concat(sp)
    |> concat(namespace)
    |> concat(sp)
    |> concat(namespace)

  obsolete_search_response =
    string("SEARCH")
    |> repeat(sp |> concat(nz_number))

  obsolete_recent_response =
    number
    |> string(" RECENT")

  mailbox_data =
    choice([
      string("FLAGS ")
      |> concat(flag_list),
      string("LIST ")
      |> concat(mailbox_list),
      esearch_response,
      string("STATUS ")
      |> concat(mailbox)
      |> string(" (")
      |> optional(status_att_list)
      |> ascii_char([?)]),
      number
      |> string(" EXISTS"),
      namespace_response,
      obsolete_search_response,
      obsolete_recent_response
    ])

  obsolete_flag_recent = string("\\Recent")

  flag_fetch = choice([flag, obsolete_flag_recent])

  msg_att_dynamic =
    string("FLAGS (")
    |> optional(
      flag_fetch
      |> repeat(
        sp
        |> concat(flag_fetch)
      )
    )
    |> ascii_char([?)])

  nstring = choice([string_, nil_])

  addr_name = nstring

  addr_adl = nstring

  addr_mailbox = nstring

  addr_host = nstring

  address =
    ascii_char([?(])
    |> concat(addr_name)
    |> concat(sp)
    |> concat(addr_adl)
    |> concat(sp)
    |> concat(addr_mailbox)
    |> concat(sp)
    |> concat(addr_host)

  ascii_char([?)])

  env_date = nstring

  env_subject = nstring

  env_sender =
    env_reply_to =
    env_to =
    env_cc =
    env_bcc =
    env_from =
    choice([
      nil_,
      ascii_char([?(])
      |> times(address, min: 1)
      |> ascii_char([?)])
    ])

  env_in_reply_to = nstring

  env_message_id = nstring

  envelope =
    ascii_char([?(])
    |> concat(env_date)
    |> concat(sp)
    |> concat(env_subject)
    |> concat(sp)
    |> concat(env_from)
    |> concat(sp)
    |> concat(env_sender)
    |> concat(sp)
    |> concat(env_reply_to)
    |> concat(sp)
    |> concat(env_to)
    |> concat(sp)
    |> concat(env_cc)
    |> concat(sp)
    |> concat(env_bcc)
    |> concat(sp)
    |> concat(env_in_reply_to)
    |> concat(sp)
    |> concat(env_message_id)
    |> ascii_char([?)])

  date_day_fixed =
    choice([
      sp
      |> concat(digit),
      times(digit, 2)
    ])

  date_month = choice(Enum.map(~w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec], &string/1))

  date_year = times(digit, 4)

  time =
    times(digit, 2)
    |> ascii_char([?:])
    |> times(digit, 2)
    |> ascii_char([?:])
    |> times(digit, 2)

  zone =
    ascii_char([?+, ?-])
    |> times(digit, 4)

  date_time =
    ascii_char([?"])
    |> concat(date_day_fixed)
    |> ascii_char([?-])
    |> concat(date_month)
    |> ascii_char([?-])
    |> concat(date_year)
    |> concat(sp)
    |> concat(time)
    |> concat(sp)
    |> concat(zone)
    |> ascii_char([?"])

  media_subtype = string_

  media_basic =
    choice([
      ascii_char([?"])
      |> choice(Enum.map(~w[APPLICATION AUDIO IMAGE FONT MESSAGE MODEL VIDEO], &string/1))
      |> ascii_char([?"]),
      string_
    ])
    |> concat(sp)
    |> concat(media_subtype)

  body_fld_param =
    choice([
      nil_,
      ascii_char([?(])
      |> concat(string_)
      |> concat(sp)
      |> concat(string_)
      |> repeat(sp |> concat(string_) |> concat(sp) |> concat(string_))
      |> ascii_char([?)])
    ])

  body_fld_id = nstring

  body_fld_desc = nstring

  body_fld_enc =
    choice([
      string_,
      ascii_char([?"])
      |> choice(Enum.map(~w[7BIT 8BIT BINARY BASE64 QUOTED-PRINTABLE], &string/1))
      |> ascii_char([?"])
    ])

  body_fld_octets = number

  media_message =
    string(~s("MESSAGE" "))
    |> choice([string("RFC822"), string("GLOBAL")])
    |> ascii_char([?"])

  body_fields =
    body_fld_param
    |> concat(sp)
    |> concat(body_fld_id)
    |> concat(sp)
    |> concat(body_fld_desc)
    |> concat(sp)
    |> concat(body_fld_enc)
    |> concat(sp)
    |> concat(body_fld_octets)

  body_type_basic =
    media_basic
    |> concat(sp)
    |> concat(body_fields)

  body_fld_lines = number64

  body_type_msg =
    media_message
    |> concat(sp)
    |> concat(body_fields)
    |> concat(sp)
    |> concat(envelope)
    |> concat(sp)
    |> concat(parsec(:body))
    |> concat(sp)
    |> concat(body_fld_lines)

  media_text =
    string(~s("TEXT" ))
    |> concat(media_subtype)

  body_type_text =
    media_text
    |> concat(sp)
    |> concat(body_fields)
    |> concat(sp)
    |> concat(body_fld_lines)

  body_fld_md5 = nstring

  body_fld_dsp =
    choice([
      nil_,
      ascii_char([?(])
      |> concat(string_)
      |> concat(sp)
      |> concat(body_fld_param)
      |> ascii_char([?)])
    ])

  body_fld_loc = nstring

  defparsec(
    :body_extension,
    choice([
      nstring,
      number,
      number64,
      ascii_char([?(])
      |> parsec(:body_extension)
      |> repeat(sp |> parsec(:body_extension))
      |> ascii_char([?)])
    ])
  )

  body_fld_lang =
    choice([
      nstring,
      ascii_char([?(])
      |> concat(string_)
      |> repeat(sp |> concat(string_))
      |> ascii_char([?)])
    ])

  body_ext_1part =
    body_fld_md5
    |> optional(
      sp
      |> concat(body_fld_dsp)
      |> optional(
        sp
        |> concat(body_fld_lang)
        |> optional(sp |> concat(body_fld_loc) |> repeat(sp |> parsec(:body_extension)))
      )
    )

  body_type_1part =
    choice([
      body_type_basic,
      body_type_msg,
      body_type_text
    ])
    |> optional(sp |> concat(body_ext_1part))

  body_ext_mpart =
    body_fld_param
    |> optional(
      sp
      |> concat(body_fld_dsp)
      |> optional(
        sp
        |> concat(body_fld_lang)
        |> optional(sp |> concat(body_fld_loc) |> repeat(sp |> parsec(:body_extension)))
      )
    )

  defparsec(
    :body_type_mpart,
    times(parsec(:body), min: 1)
    |> concat(sp)
    |> concat(media_subtype)
    |> optional(sp |> concat(body_ext_mpart))
  )

  defparsec(
    :body,
    ascii_char([?(])
    |> choice([body_type_1part, parsec(:body_type_mpart)])
    |> ascii_char([?)])
  )

  header_fld_name = astring

  header_list =
    ascii_char([?(])
    |> concat(header_fld_name)
    |> repeat(sp |> concat(header_fld_name))
    |> ascii_char([?)])

  section_msgtext =
    choice([
      string("HEADER"),
      string("TEXT"),
      string("HEADER.FIELDS")
      |> optional(string(".NOT"))
      |> concat(sp)
      |> concat(header_list)
    ])

  section_part = nz_number |> repeat(ascii_char([?.]) |> concat(nz_number))

  section_text = choice([string("MIME"), section_msgtext])

  section_spec =
    choice([
      section_msgtext,
      section_part
      |> optional(ascii_char([?.]) |> concat(section_text))
    ])

  section =
    ascii_char([?[])
    |> concat(section_spec)
    |> ascii_char([?]])

  section_binary =
    ascii_char([?[])
    |> optional(section_part)
    |> ascii_char([?]])

  msg_att_static =
    choice([
      string("ENVELOPE ") |> concat(envelope),
      string("INTERNALDATE ") |> concat(date_time),
      string("RFC822.SIZE ") |> concat(number64),
      string("BODY") |> optional(string("STRUCTURE")) |> concat(sp) |> parsec(:body),
      string("BODY")
      |> concat(section)
      |> optional(ascii_char([?<]) |> concat(number) |> ascii_char([?>]))
      |> concat(sp)
      |> concat(nstring),
      string("BINARY") |> concat(section_binary) |> concat(sp) |> choice([nstring, literal8]),
      string("BINARY.SIZE") |> concat(section_binary) |> concat(sp) |> concat(number),
      string("UID ") |> concat(uniqueid)
    ])

  msg_att =
    ascii_char([?(])
    |> choice([msg_att_dynamic, msg_att_static])
    |> repeat(
      sp
      |> choice([
        msg_att_dynamic,
        msg_att_static
      ])
    )

  ascii_char([?)])

  message_data =
    nz_number
    |> concat(sp)
    |> choice([
      string("EXPUNGE"),
      string("FETCH ")
      |> concat(msg_att)
    ])

  enable_data =
    string("ENABLED")
    |> repeat(sp |> concat(capability))

  response_data =
    string("* ")
    |> choice([
      resp_cond_state,
      resp_cond_bye,
      mailbox_data,
      message_data,
      capability_data,
      enable_data
    ])
    |> concat(crlf)

  response_fatal =
    string("* ")
    |> concat(resp_cond_bye)
    |> concat(crlf)

  response_done = choice([response_tagged, response_fatal])

  response =
    choice([response_data, continue_req, response_done])

  defparsec(:response, response)
end
