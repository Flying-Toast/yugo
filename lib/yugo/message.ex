defmodule Yugo.Message do
  defstruct [
    :bcc,
    :body,
    :cc,
    :date,
    :flags,
    :in_reply_to,
    :message_id,
    :reply_to,
    :sender,
    :subject,
    :to,
    :from
  ]

  alias Yugo.Message
  alias Yugo.Parser

  def package(%{envelope: envelope, body: body, flags: flags, body_structure: body_structure}) do
    %Message{
      bcc: Map.get(envelope, :bcc),
      body: normalize_structure(body, body_structure),
      cc: Map.get(envelope, :cc),
      date: Map.get(envelope, :date),
      flags: flags,
      in_reply_to: Map.get(envelope, :in_reply_to),
      message_id: Map.get(envelope, :message_id),
      reply_to: Map.get(envelope, :reply_to),
      sender: Map.get(envelope, :sender),
      subject: Map.get(envelope, :subject),
      to: Map.get(envelope, :to),
      from: Map.get(envelope, :from)
    }
  end

  defp normalize_structure(body, structure) do
    body
    |> combine_bodies_if_multipart()
    |> get_part_structures(structure)
  end

  defp combine_bodies_if_multipart(_, depth \\ 0)
  defp combine_bodies_if_multipart([body], _depth), do: body
  defp combine_bodies_if_multipart(body, _depth) when is_tuple(body), do: body

  defp combine_bodies_if_multipart(bodies, depth) when is_list(bodies) and length(bodies) > 1 do
    bodies
    |> Enum.group_by(fn {path, _} -> Enum.at(path, depth) end)
    |> Map.values()
    |> Enum.map(&combine_bodies_if_multipart(&1, depth + 1))
  end

  defp get_part_structures(
         {_, content},
         {:onepart, %{mime_type: mime_type, params: params, encoding: encoding}}
       ) do
    {mime_type, params, Parser.decode_body(content, encoding)}
  end

  defp get_part_structures({[index | path], content}, {:multipart, parts}) do
    get_part_structures({path, content}, Enum.at(parts, index - 1))
  end

  defp get_part_structures(bodies, structure) when is_list(bodies) do
    Enum.map(bodies, &get_part_structures(&1, structure))
  end
end
