defmodule UgotMail.IMAPParser do
  @moduledoc false

  @response_status "(?<resp_status>OK|NO|BAD) (?<resp_text>.*)"

  def parse_response(data) when is_binary(data) do
    data = String.replace_suffix(data, "\r\n", "")

    case data do
      <<"* ", rest::binary>> ->
        parse_untagged(rest)

      <<"+ ", rest::binary>> ->
        parse_continuation(rest)

      _ ->
        parse_tagged(data)
    end
  end

  # resp is the rest of the response, after the "<tag> "
  defp parse_tagged(resp) do
    caps = Regex.named_captures(~r/^(?<tag>\S+) #{@response_status}/i, resp)
    status = atomize_status_code(caps["resp_status"])

    [tagged_response: {String.to_integer(caps["tag"]), status}]
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

  # `resp` has the leading "+ " removed
  defp parse_continuation(resp) do
  end
end
