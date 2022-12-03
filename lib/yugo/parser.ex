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

  @doc """
  Parses a response from the server into a list of "actions".

  "Actions" are terms that specify a change to the client state that happens
  in response to a certain server event. For example, parsing this "CAPABILITY" response
  generates a `:capabilities` action:

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
        Logger.info(~s([Yugo] didn't parse response: "* OK #{inspect(resp)}"))
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
        Logger.info(~s([Yugo] didn't parse response: "* #{inspect(resp)}"))
        []
    end
  end

  def parse_msg_atts(rest), do: parse_msg_atts_aux(rest, [])

  # parses the <msg-att> from the RFC's APRS, minus the outer parenthesis
  defp parse_msg_atts_aux("", acc), do: acc
  defp parse_msg_atts_aux(rest, acc) do
    {att, rest} = parse_one_att(rest)
    parse_msg_atts_aux(rest, [att | acc])
  end

  defp parse_one_att(rest) do
    [name, rest] = Regex.run(~r/^ ?(\S+) (.*)$/is, rest, capture: :all_but_first)
    name = String.upcase(name)

    case name do
      "FLAGS" ->
        {flags, rest} = parse_flags(rest)
        {{:flags, flags}, rest}
    end
  end

  # takes a list of parser functions to parse an IMAP parenthesized list
  defp parse_list(<<?(, rest::binary>>, parsers), do: parse_list_aux(rest, parsers, [])

  defp parse_list_aux(<<?), rest::binary>>, [], acc), do: {Enum.reverse(acc), rest}
  defp parse_list_aux(<<?\s, rest::binary>>, parsers, acc), do: parse_list_aux(rest, parsers, acc)
  defp parse_list_aux(rest, [p | parsers], acc) do
    {parser_output, rest} = p.(rest)
    parse_list_aux(rest, parsers, [parser_output | acc])
  end

  defp parse_flags(<<?(, rest::binary>>), do: parse_flags_aux(rest, [], [])
  defp parse_flags_aux(<<?\s, rest::binary>>, flag_acc, acc), do: parse_flags_aux(rest, [], [to_string(Enum.reverse(flag_acc)) | acc])
  defp parse_flags_aux(<<?), rest::binary>>, flag_acc, acc) do
    if flag_acc == '' do
      {acc, rest}
    else
      {[to_string(Enum.reverse(flag_acc)) | acc], rest}
    end
  end
  defp parse_flags_aux(<<c, rest::binary>>, flag_acc, acc), do: parse_flags_aux(rest, [c | flag_acc], acc)

  defp string(<<?", _::binary>> = rest), do: quoted_string(rest)
  defp string(<<?{, _::binary>> = rest), do: literal(rest)

  def nstring(rest) do
    if Regex.match?(~r/^NIL/is, rest) do
      <<_::binary-size(3), rest::binary>> = rest
      {nil, rest}
    else
      string(rest)
    end
  end

  defp quoted_string(<<?", rest::binary>>) do
    quoted_string_contents(rest, [])
  end

  defp quoted_string_contents(<<?", rest::binary>>, acc), do: {to_string(Enum.reverse(acc)), rest}
  defp quoted_string_contents(<<"\\\"", rest::binary>>, acc), do: quoted_string_contents(rest, [?" | acc])
  defp quoted_string_contents(<<"\\\\", rest::binary>>, acc), do: quoted_string_contents(rest, [?\\ | acc])
  defp quoted_string_contents(<<ch, rest::binary>>, acc), do: quoted_string_contents(rest, [ch | acc])

  defp charlist_to_integer(c) do
    {int, []} = :string.to_integer(c)
    int
  end

  defp literal(<<?{, rest::binary>>), do: literal_aux(rest, [])
  defp literal_aux(<<"}\r\n", rest::binary>>, acc) do
    num_octets = charlist_to_integer(Enum.reverse(acc))
    <<octets::binary-size(num_octets), rest::binary>> = rest
    {octets, rest}
  end
  defp literal_aux(<<n, rest::binary>>, acc), do: literal_aux(rest, [n | acc])
end
