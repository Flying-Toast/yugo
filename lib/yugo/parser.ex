defmodule Yugo.Parser do
  @moduledoc false

  require Logger

  def system_flags_to_atoms(flags) do
    for flag <- flags do
      case String.upcase(flag) do
        "\\SEEN" -> :seen
        "\\ANSWERED" -> :answered
        "\\FLAGGED" -> :flagged
        "\\DRAFT" -> :draft
        "\\DELETED" -> :deleted
        _ -> nil
      end
    end
    |> Enum.filter(&Function.identity/1)
  end

  def decode_body(body, encoding) do
    case encoding do
      "BASE64" ->
        body
        |> String.replace("\r\n", "")
        |> Base.decode64!()

      "QUOTED-PRINTABLE" ->
        body = String.replace(body, "=\r\n", "")

        Regex.replace(~r/=(..)/, body, fn _, x ->
          {n, _} = Integer.parse(x, 16)
          n
        end)

      _ ->
        body
    end
  end

  @doc """
  Parses a response from the server into a list of "actions".

  "Actions" are terms that specify a change to the client state that happens
  in response to a certain server event. For example, parsing this "FLAGS" response
  generates an `:applicable_flags` action:

      iex(2)> Yugo.Parser.parse_response ~S|* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)|
      [applicable_flags: ["\\ANSWERED", "\\FLAGGED", "\\DELETED", "\\SEEN", "\\DRAFT"]]
  """
  def parse_response(data) when is_binary(data) do
    data = String.replace_suffix(data, "\r\n", "")

    case data do
      <<"* ", rest::binary>> ->
        parse_untagged(rest)

      <<"+ ", _::binary>> ->
        [:continuation]

      _ ->
        parse_tagged(data)
    end
  end

  # resp is the rest of the response, after the "<tag> "
  defp parse_tagged(resp) do
    caps =
      Regex.named_captures(~r/^(?<tag>\S+) (?<resp_status>OK|NO|BAD) (?<resp_text>.*)/is, resp)

    status = atomize_status_code(caps["resp_status"])

    [tagged_response: {String.to_integer(caps["tag"]), status, caps["resp_text"]}]
  end

  defp atomize_status_code(code) do
    case String.downcase(code) do
      "ok" -> :ok
      "no" -> :no
      "bad" -> :bad
      "preauth" -> :preauth
      "bye" -> :bye
    end
  end

  # `resp` has the leading "* " removed
  # returns a keyword list of actions
  defp parse_untagged(resp) do
    case Regex.run(~r/^(OK|NO|BAD|PREAUTH|BYE) (.*)$/is, resp, capture: :all_but_first) do
      [status, rest_of_packet] ->
        status = atomize_status_code(status)
        parse_untagged_with_status(rest_of_packet, status)

      nil ->
        parse_untagged_no_status(resp)
    end
  end

  # TODO: find an elegant way to do parse_untagged_[with/without]_status without all the duplication

  defp parse_untagged_with_status(resp, :ok) do
    cond do
      Regex.match?(~r/^\[PERMANENTFLAGS \(/is, resp) ->
        [flagstring] =
          Regex.run(~r/^\[PERMANENTFLAGS \((.*)\)\]/is, resp, capture: :all_but_first)

        String.split(flagstring, " ", trim: true)
        |> Enum.map(&String.upcase/1)
        |> then(&[permanent_flags: &1])

      Regex.match?(~r/^\[UNSEEN /is, resp) ->
        [num] = Regex.run(~r/^\[UNSEEN (\d+)\]/is, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [first_unseen: num]

      Regex.match?(~r/^\[UIDVALIDITY /is, resp) ->
        [num] = Regex.run(~r/^\[UIDVALIDITY (\d+)\]/is, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [uid_validity: num]

      Regex.match?(~r/^\[UIDNEXT /is, resp) ->
        [num] = Regex.run(~r/^\[UIDNEXT (\d+)\]/is, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [uid_next: num]

      true ->
        []
    end
  end

  defp parse_untagged_no_status(resp) do
    cond do
      Regex.match?(~r/^CAPABILITY /is, resp) ->
        resp
        |> String.upcase()
        |> String.replace_prefix("CAPABILITY ", "")
        |> String.split(" ", trim: true)
        |> then(&[capabilities: &1])

      Regex.match?(~r/^FLAGS /is, resp) ->
        [flagstring] = Regex.run(~r/^FLAGS \((.*)\)/is, resp, capture: :all_but_first)

        String.split(flagstring, " ", trim: true)
        |> Enum.map(&String.upcase/1)
        |> then(&[applicable_flags: &1])

      Regex.match?(~r/^\d+ EXISTS/is, resp) ->
        [num] = Regex.run(~r/^(\d+) /is, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [num_exists: num]

      Regex.match?(~r/^\d+ RECENT/is, resp) ->
        [num] = Regex.run(~r/^(\d+) /is, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [num_recent: num]

      Regex.match?(~r/^\d+ EXPUNGE/is, resp) ->
        [num] = Regex.run(~r/^(\d+) /is, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [expunge: num]

      Regex.match?(~r/^\d+ FETCH /is, resp) ->
        [seqnum, fetchdata] =
          Regex.run(~r/^(\d+) FETCH \((.*)\)$/is, resp, capture: :all_but_first)

        seqnum = String.to_integer(seqnum)

        parse_msg_atts(fetchdata)
        |> Enum.map(fn {attr, value} -> {:fetch, {seqnum, attr, value}} end)

      true ->
        []
    end
  end

  defp parse_msg_atts(rest), do: parse_msg_atts_aux(rest, [])

  # parses the <msg-att> from the RFC's APRS, minus the outer parenthesis
  defp parse_msg_atts_aux("", acc), do: acc

  defp parse_msg_atts_aux(rest, acc) do
    case parse_one_att(rest) do
      {att, rest} ->
        parse_msg_atts_aux(rest, [att | acc])

      _ ->
        acc
    end
  end

  defp parse_one_att(input) do
    [name, rest] = Regex.run(~r/^ ?(\S+) (.*)$/is, input, capture: :all_but_first)
    name = String.upcase(name)

    cond do
      name == "FLAGS" ->
        {flags, rest} = parse_variable_length_list(rest, &parse_flag/1)
        {{:flags, flags}, rest}

      name == "ENVELOPE" ->
        {[date, subject, from, sender, reply_to, to, cc, bcc, in_reply_to, message_id], rest} =
          parse_list(
            rest,
            [
              &parse_nstring/1,
              &parse_nstring/1,
              &parse_address_list/1,
              &parse_address_list/1,
              &parse_address_list/1,
              &parse_address_list/1,
              &parse_address_list/1,
              &parse_address_list/1,
              &parse_nstring/1,
              &parse_nstring/1
            ]
          )

        envelope = %{
          date: rfc5322_to_datetime(date),
          subject: subject,
          from: from,
          sender: sender,
          reply_to: reply_to,
          to: to,
          cc: cc,
          bcc: bcc,
          in_reply_to: in_reply_to,
          message_id: message_id
        }

        {{:envelope, envelope}, rest}

      name == "BODY" ->
        parse_body(rest)

      name == "UID" ->
        {uid, rest} = parse_number(rest)
        {{:uid, uid}, rest}

      Regex.match?(~r/BODY\[/, name) ->
        [body_number] = Regex.run(~r/BODY\[([0-9.]+)\]/, name, capture: :all_but_first)

        body_number =
          body_number
          |> String.split(".")
          |> Enum.map(&String.to_integer/1)

        {content, rest} = parse_string(rest)
        {{:body_content, {body_number, content}}, rest}

      # name == "INTERNALDATE" ->
      #   [date, rest] = Regex.run(~r/"(?:\\.|[^"\\])*" (.*)/, rest)
      #   {{:internal_date, rfc5322_to_datetime(date)}, rest}

      true ->
        Logger.warning("[#{inspect(Yugo.Client)}] [Parser] #{inspect(input)}")
        nil
    end
  end

  # takes a list of parser functions to parse an IMAP parenthesized list
  # pass `:lax` instead of `:strict` if it shouldn't raise when the list ends but there are still unused parsers.
  defp parse_list(<<?(, rest::binary>>, parsers, strict? \\ :strict),
    do: parse_list_aux(rest, parsers, [], strict?)

  defp parse_list_aux(<<?), rest::binary>>, [], acc, :strict), do: {Enum.reverse(acc), rest}
  defp parse_list_aux(<<?), rest::binary>>, _, acc, :lax), do: {Enum.reverse(acc), rest}

  defp parse_list_aux(<<?\s, rest::binary>>, parsers, acc, strict?),
    do: parse_list_aux(rest, parsers, acc, strict?)

  defp parse_list_aux(rest, [p | parsers], acc, strict?) do
    {parser_output, rest} = p.(rest)
    parse_list_aux(rest, parsers, [parser_output | acc], strict?)
  end

  defp parse_variable_length_list(<<?(, rest::binary>>, parser),
    do: parse_variable_length_list_aux(rest, parser, [])

  defp parse_variable_length_list_aux(<<?), rest::binary>>, _, acc), do: {Enum.reverse(acc), rest}

  defp parse_variable_length_list_aux(<<?\s, rest::binary>>, parser, acc),
    do: parse_variable_length_list_aux(rest, parser, acc)

  defp parse_variable_length_list_aux(rest, parser, acc) do
    {parser_output, rest} = parser.(rest)
    parse_variable_length_list_aux(rest, parser, [parser_output | acc])
  end

  defp parse_flag(rest) do
    [flag, rest] = Regex.run(~r/^([^ \)]+)(.*)/is, rest, capture: :all_but_first)
    {flag, rest}
  end

  # e.g. for key-value pairs in <body-fld-param>
  defp parse_string_pair(rest) do
    {a, <<?\s, rest::binary>>} = parse_string(rest)
    {b, rest} = parse_string(rest)
    {{a, b}, rest}
  end

  defp parse_address(rest) do
    {[name, _adl, mailbox, host], rest} =
      parse_list(rest, [&parse_nstring/1, &parse_nstring/1, &parse_nstring/1, &parse_nstring/1])

    {{name, "#{String.downcase(mailbox)}@#{String.downcase(host)}"}, rest}
  end

  defp parse_address_list(rest) do
    if Regex.match?(~r/^NIL/is, rest) do
      <<_::binary-size(3), rest::binary>> = rest
      {[], rest}
    else
      parse_variable_length_list(rest, &parse_address/1)
    end
  end

  defp parse_string(<<?", _::binary>> = rest), do: parse_quoted_string(rest)
  defp parse_string(<<?{, _::binary>> = rest), do: parse_literal(rest)

  defp parse_nstring(rest) do
    if Regex.match?(~r/^NIL/is, rest) do
      <<_::binary-size(3), rest::binary>> = rest
      {nil, rest}
    else
      parse_string(rest)
    end
  end

  defp parse_number(rest), do: parse_number_aux(rest, [])

  defp parse_number_aux(<<c, rest::binary>>, acc) when c in ?0..?9,
    do: parse_number_aux(rest, [c | acc])

  defp parse_number_aux(rest, acc) do
    {int, []} = :string.to_integer(Enum.reverse(acc))
    {int, rest}
  end

  # parses a number or returns `{nil, rest}` if it cant.
  defp parse_optional_number(<<c, _::binary>> = rest) when c in ?0..?9, do: parse_number(rest)
  defp parse_optional_number(rest), do: {nil, rest}

  defp parse_quoted_string(<<?", rest::binary>>) do
    parse_quoted_string_aux(rest, [])
  end

  defp parse_quoted_string_aux(<<?", rest::binary>>, acc),
    do: {to_string(Enum.reverse(acc)), rest}

  defp parse_quoted_string_aux(<<"\\\"", rest::binary>>, acc),
    do: parse_quoted_string_aux(rest, [?" | acc])

  defp parse_quoted_string_aux(<<"\\\\", rest::binary>>, acc),
    do: parse_quoted_string_aux(rest, [?\\ | acc])

  defp parse_quoted_string_aux(<<ch, rest::binary>>, acc),
    do: parse_quoted_string_aux(rest, [ch | acc])

  defp parse_literal(<<?{, rest::binary>>) do
    {num_octets, <<"}\r\n", rest::binary>>} = parse_number(rest)
    <<octets::binary-size(num_octets), rest::binary>> = rest
    {octets, rest}
  end

  defp rfc5322_to_datetime(string) do
    monthname = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

    parts =
      Regex.named_captures(
        ~r/^(?:[^,]+,)?\s*(?<day>\d+)\s+(?<month>#{Enum.join(monthname, "|")})\s+(?<year>\d{4})\s+(?<hour>\d{2}):(?<minute>\d{2}):?(?<second>\d{2})?\s+(?<offset_sign>[+\-])(?<offset_hours>\d{2})(?<offset_minutes>\d{2})/i,
        string
      )

    month = 1 + Enum.find_index(monthname, &(&1 == parts["month"]))

    date =
      Date.new!(
        String.to_integer(parts["year"]),
        month,
        String.to_integer(parts["day"])
      )

    time =
      Time.new!(
        String.to_integer(parts["hour"]),
        String.to_integer(parts["minute"]),
        String.to_integer(parts["second"] || 0)
      )

    DateTime.new!(date, time)
    |> DateTime.add(String.to_integer(parts["offset_sign"] <> parts["offset_hours"]), :hour)
    |> DateTime.add(String.to_integer(parts["offset_sign"] <> parts["offset_minutes"]), :minute)
  end

  defp parse_body(<<"((", _::binary>> = rest) do
    <<?(, rest::binary>> = rest
    {result, <<?), rest::binary>>} = parse_body_type_mpart(rest)
    {result, rest}
  end

  defp parse_body(rest), do: parse_body_type_1part(rest)

  defp parse_body_type_mpart(rest), do: parse_body_type_mpart_aux(rest, [])

  defp parse_body_type_mpart_aux(<<?\s, rest::binary>>, acc) do
    {_media_subtype, rest} = parse_string(rest)
    {{:body, {:multipart, acc}}, rest}
  end

  defp parse_body_type_mpart_aux(rest, acc) do
    {{:body, bodies}, rest} = parse_body(rest)
    parse_body_type_mpart_aux(rest, acc ++ [bodies])
  end

  defp parse_body_type_1part(rest) do
    parse_body_fld_param = fn rest ->
      if Regex.match?(~r/^NIL/is, rest) do
        <<_::binary-size(3), rest::binary>> = rest
        {[], rest}
      else
        parse_variable_length_list(rest, &parse_string_pair/1)
      end
    end

    # TODO: support body-type-msg

    {[mime1, mime2, params, _id, _desc, enc, _octets | _rest_opt], rest} =
      parse_list(
        rest,
        [
          &parse_string/1,
          &parse_string/1,
          parse_body_fld_param,
          &parse_nstring/1,
          &parse_nstring/1,
          &parse_string/1,
          &parse_number/1,
          &parse_optional_number/1
        ],
        :lax
      )

    mime_type = "#{String.downcase(mime1)}/#{String.downcase(mime2)}"

    body = %{
      mime_type: mime_type,
      encoding: String.upcase(enc),
      params: Map.new(params)
    }

    {{:body, {:onepart, body}}, rest}
  end
end
