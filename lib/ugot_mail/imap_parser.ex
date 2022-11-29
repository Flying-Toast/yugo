defmodule UgotMail.IMAPParser do
  import NimbleParsec

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
end
