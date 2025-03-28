defmodule Yugo.Action do
  alias Yugo.Conn
  alias Yugo.Parser

  require Logger

  def apply({:capabilities, caps}, conn) do
    %{conn | capabilities: caps}
  end

  def apply({:tagged_response, {tag, status, text}}, conn) do
    {%{on_response: on_response, command: command}, conn} = Conn.pop_tag_map(conn, tag)

    case status do
      :ok ->
        on_response.(conn, :ok, text)

      status when status in ~w(bad no)a ->
        string_status = status |> to_string() |> String.upcase()
        Logger.error("[#{inspect(__MODULE__)}] [#{command}] [#{string_status}] #{text}")
        conn
    end
  end

  def apply(:continuation, conn) do
    conn
  end

  def apply({:applicable_flags, flags}, conn) do
    %{conn | applicable_flags: flags}
  end

  def apply({:permanent_flags, flags}, conn) do
    %{conn | permanent_flags: flags}
  end

  def apply({:num_exists, num}, %Conn{num_exists: num_exists} = conn) when num_exists < num do
    conn
    |> Conn.map_unprocessed_messages(fn unprocessed_messages ->
      range = (conn.num_exists + 1)..num

      range
      |> Enum.reduce(%{}, &Map.put(&2, &1, %{}))
      |> Map.merge(unprocessed_messages)
    end)
    |> Conn.map_num_exists(fn _ -> num end)
  end

  def apply({:num_exists, num}, conn) do
    Conn.map_num_exists(conn, fn _ -> num end)
  end

  def apply({:num_recent, num}, conn) do
    %{conn | num_recent: num}
  end

  def apply({:first_unseen, num}, conn) do
    %{conn | first_unseen: num}
  end

  def apply({:uid_validity, num}, conn) do
    %{conn | uid_validity: num}
  end

  def apply({:uid_next, num}, conn) do
    %{conn | uid_next: num}
  end

  def apply({:expunge, expunged_num}, conn) do
    conn
    |> Conn.map_num_exists(&(&1 + 1))
    |> Conn.expunge_messages(expunged_num)
  end

  def apply({:fetch, {seq_num, :flags, flags}}, conn) do
    if Map.has_key?(conn.unprocessed_messages, seq_num) do
      flags = Parser.system_flags_to_atoms(flags)

      Conn.map_unprocessed_message(conn, seq_num, %{flags: flags})
    else
      conn
    end
  end

  def apply({:fetch, {seq_num, :envelope, envelope}}, conn) do
    if Map.has_key?(conn.unprocessed_messages, seq_num) do
      Conn.map_unprocessed_message(conn, seq_num, %{envelope: envelope})
    else
      conn
    end
  end

  def apply({:fetch, {seq_num, :body, one_or_mpart}}, conn) do
    if Conn.has_unprocessed_message?(conn, seq_num) do
      Conn.map_unprocessed_message(conn, seq_num, %{body_structure: one_or_mpart})
    else
      conn
    end
  end

  def apply({:fetch, {seq_num, :body_content, {body_number, content}}}, conn) do
    case Map.get(conn.unprocessed_messages, seq_num) do
      nil ->
        conn

      msg ->
        body =
          case msg.body_structure do
            {:onepart, _} ->
              {body_number, content}

            {:multipart, _} ->
              [{body_number, content} | msg[:body] || []]
          end

        Conn.map_unprocessed_message(conn, seq_num, %{body: body})
    end
  end

  def apply({:fetch, {_seq_num, :uid, _uid}}, conn) do
    conn
  end
end
