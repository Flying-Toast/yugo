defmodule UgotMail.IMAPParser do
  @moduledoc false

  @response_status "(?<resp_status>OK|NO|BAD) (?<resp_text>.*)"

  @doc """
  Parses a response from the server into a list of "actions".

  "Actions" are terms that specify a change to the client state that happens
  in response to a certain server event. For example, parsing this "CAPABILITY" response
  generates a `:capabilities` action:

      iex> UgotMail.IMAPParser.parse_response "* CAPABILITY IMAP4rev1 SASL-IR LOGIN-REFERRALS ID ENABLE IDLE LITERAL+ AUTH=PLAIN"
      [capabilities: ["IMAP4REV1", "SASL-IR", "LOGIN-REFERRALS", "ID", "ENABLE", "IDLE", "LITERAL+", "AUTH=PLAIN"]]
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
    caps = Regex.named_captures(~r/^(?<tag>\S+) #{@response_status}/i, resp)
    status = atomize_status_code(caps["resp_status"])

    [tagged_response: {String.to_integer(caps["tag"]), status, caps["resp_text"]}]
  end

  defp atomize_status_code(code) do
    case String.downcase(code) do
      "ok" -> :ok
      "no" -> :no
      "bad" -> :bad
    end
  end

  # `resp` has the leading "* " removed
  # returns a keyword list of actions
  defp parse_untagged(resp) do
    cond do
      Regex.match?(~r/^CAPABILITY /i, resp) ->
        resp
        |> String.upcase()
        |> String.replace_prefix("CAPABILITY ", "")
        |> String.split(" ")
        |> then(&[capabilities: &1])
    end
  end
end
