defmodule Yugo.MsgAttParser.Helpers do
  @moduledoc false

  def to_upcased_string(x) do
    x
    |> to_string()
    |> String.upcase()
  end

  def anycase_string(s) do
    [String.downcase(s), String.upcase(s)]
    |> Enum.map(&to_charlist/1)
    |> Enum.zip_with(& &1)
    |> Enum.reduce(NimbleParsec.empty(), fn x, acc -> NimbleParsec.ascii_char(acc, x) end)
    |> NimbleParsec.reduce({Yugo.MsgAttParser.Helpers, :to_upcased_string, []})
  end

  def att_name(s) do
    anycase_string(s)
    |> NimbleParsec.ascii_char([?\s])
    |> NimbleParsec.ignore()
  end
end

defmodule Yugo.MsgAttParser do
  @moduledoc false

  import Yugo.MsgAttParser.Helpers, only: [anycase_string: 1, att_name: 1]
  import NimbleParsec

  defp n_literal_octets(
         rest,
         [num_octets | acc],
         context,
         _line,
         _offset
       ) do
    <<octets::binary-size(num_octets), rest::binary>> = rest
    {rest, [octets | acc], context}
  end

  literal =
    ignore(ascii_char([?{]))
    |> integer(min: 1)
    |> ignore(string("}\r\n"))
    |> post_traverse({:n_literal_octets, []})

  quoted =
    ignore(ascii_char([?"]))
    |> repeat(
      choice([
        string(~S(\"))
        |> replace(?"),
        string(~S(\\))
        |> replace(?\\),
        ascii_char(not: ?\\, not: ?")
      ])
    )
    |> ignore(ascii_char([?"]))

  string =
    choice([
      quoted,
      literal
    ])
    |> reduce(:to_string)

  nil_ = anycase_string("NIL") |> replace(nil)

  nstring =
    choice([
      nil_,
      string
    ])

  uid =
    att_name("UID")
    |> integer(min: 1)
    |> unwrap_and_tag(:uid)

  rfc822_header =
    att_name("RFC822.HEADER")
    |> concat(nstring)
    |> unwrap_and_tag(:rfc822_header)

  rfc822 =
    att_name("RFC822")
    |> concat(nstring)
    |> unwrap_and_tag(:rfc822)

  rfc822_text =
    att_name("RFC822.TEXT")
    |> concat(nstring)
    |> unwrap_and_tag(:rfc822_text)

  rfc822_size =
    att_name("RFC822.SIZE")
    |> integer(min: 1)
    |> unwrap_and_tag(:rfc822_size)

  flag_name =
    ascii_char(not: ?\s, not: ?))
    |> times(min: 1)
    |> reduce(:to_string)

  flags =
    att_name("FLAGS")
    |> ignore(ascii_char([?(]))
    |> optional(
      flag_name
      |> repeat(ascii_char([?\s]) |> ignore() |> concat(flag_name))
    )
    |> ignore(ascii_char([?)]))
    |> tag(:flags)

  address =
    ignore(ascii_char([?(]))
    # addr-name
    |> concat(nstring)
    |> ignore(ascii_char([?\s]))
    # addr-adl
    |> concat(nstring)
    |> ignore(ascii_char([?\s]))
    # addr-mailbox
    |> concat(nstring)
    |> ignore(ascii_char([?\s]))
    # addr-host
    |> concat(nstring)
    |> ignore(ascii_char([?)]))

  address_list =
    choice([
      nil_,
      ignore(ascii_char([?(]))
      |> times(address, min: 1)
      |> ignore(ascii_char([?)]))
    ])

  envelope_value =
    ignore(ascii_char([?(]))
    |> tag(nstring, :date)
    |> ignore(ascii_char([?\s]))
    |> tag(nstring, :subject)
    |> ignore(ascii_char([?\s]))
    |> tag(address_list, :from)
    |> ignore(ascii_char([?\s]))
    |> tag(address_list, :sender)
    |> ignore(ascii_char([?\s]))
    |> tag(address_list, :reply_to)
    |> ignore(ascii_char([?\s]))
    |> tag(address_list, :to)
    |> ignore(ascii_char([?\s]))
    |> tag(address_list, :cc)
    |> ignore(ascii_char([?\s]))
    |> tag(address_list, :bcc)
    |> ignore(ascii_char([?\s]))
    |> tag(nstring, :in_reply_to)
    |> ignore(ascii_char([?\s]))
    |> tag(nstring, :message_id)
    |> ignore(ascii_char([?)]))
    |> tag(:envelope_value)

  envelope =
    att_name("ENVELOPE")
    |> concat(envelope_value)
    |> unwrap_and_tag(:envelope)

  # "INTERNALDATE" SP date-time /
  # "BODY" SP body /
  # "BODYSTRUCTURE" SP body /
  # "BODY" section ["<" number ">"] SP nstring /
  msg_att =
    choice([
      uid,
      rfc822_header,
      rfc822,
      rfc822_text,
      rfc822_size,
      flags,
      envelope
    ])

  defparsec(
    :msg_atts,
    optional(
      msg_att
      |> repeat(ignore(ascii_char([?\s])) |> concat(msg_att))
    )
    |> eos()
  )
end
