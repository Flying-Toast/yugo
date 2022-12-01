defmodule Yugo.Parser do
  @moduledoc false

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
      Regex.named_captures(~r/^(?<tag>\S+) (?<resp_status>OK|NO|BAD) (?<resp_text>.*)/i, resp)

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
    case Regex.run(~r/^(OK|NO|BAD|PREAUTH|BYE) (.*)$/i, resp, capture: :all_but_first) do
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
      Regex.match?(~r/^\[PERMANENTFLAGS \(/i, resp) ->
        [flagstring] = Regex.run(~r/^\[PERMANENTFLAGS \((.*)\)\]/i, resp, capture: :all_but_first)

        String.split(flagstring, " ", trim: true)
        |> Enum.map(&String.upcase/1)
        |> then(&[permanent_flags: &1])

      Regex.match?(~r/^\[UNSEEN /i, resp) ->
        [num] = Regex.run(~r/^\[UNSEEN (\d+)\]/i, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [first_unseen: num]

      Regex.match?(~r/^\[UIDVALIDITY /i, resp) ->
        [num] = Regex.run(~r/^\[UIDVALIDITY (\d+)\]/i, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [uid_validity: num]

      Regex.match?(~r/^\[UIDNEXT /i, resp) ->
        [num] = Regex.run(~r/^\[UIDNEXT (\d+)\]/i, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [uid_next: num]
    end
  end

  defp parse_untagged_no_status(resp) do
    cond do
      Regex.match?(~r/^CAPABILITY /i, resp) ->
        resp
        |> String.upcase()
        |> String.replace_prefix("CAPABILITY ", "")
        |> String.split(" ", trim: true)
        |> then(&[capabilities: &1])

      Regex.match?(~r/^FLAGS /i, resp) ->
        [flagstring] = Regex.run(~r/^FLAGS \((.*)\)/i, resp, capture: :all_but_first)

        String.split(flagstring, " ", trim: true)
        |> Enum.map(&String.upcase/1)
        |> then(&[applicable_flags: &1])

      Regex.match?(~r/^\d+ EXISTS/i, resp) ->
        [num] = Regex.run(~r/^(\d+) /, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [num_exists: num]

      Regex.match?(~r/^\d+ RECENT/i, resp) ->
        [num] = Regex.run(~r/^(\d+) /, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [num_recent: num]

      Regex.match?(~r/^\d+ EXPUNGE/i, resp) ->
        [num] = Regex.run(~r/^(\d+) /, resp, capture: :all_but_first)
        num = String.to_integer(num)
        [expunge: num]

      true ->
        raise "Unparseable response: #{inspect(resp)}"
    end
  end
end
