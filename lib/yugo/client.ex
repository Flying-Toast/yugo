defmodule Yugo.Client do
  @moduledoc """
  A persistent connection to an IMAP server.

  Normally you do not call the functions in this module directly, but rather start a [`Client`](`Yugo.Client`) as part
  of your application's supervision tree. For example:

      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = [
            {Yugo.Client,
             name: :example_client,
             server: "imap.example.com",
             username: "me@example.com",
             password: "pa55w0rd"}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  See [`start_link`](`Yugo.Client.start_link/1`) for a list of possible arguments.
  """

  use GenServer
  alias Yugo.{Conn, Parser, Filter}

  @typedoc """
  The identifier used to refer to a [`Client`](`Yugo.Client`).
  """
  @type name :: term

  @doc """
  Starts an IMAP client process linked to the calling process.

  Takes arguments as a keyword list.

  ## Arguments

    * `:username` - Required. Username used to log in.

    * `:password` - Required. Password used to log in.

    * `:name` - Required. A name used to reference this [`Client`](`Yugo.Client`). Can be any term.

    * `:server` - Required. The location of the IMAP server, e.g. `"imap.example.com"`.

    * `:port` - The port to connect to the server via. Defaults to `993`.

    * `:tls` - Whether or not to connect using TLS. Defaults to `true`. If you set this to `false`,
    Yugo will make the initial connection without TLS, then upgrade to a TLS connection (using STARTTLS)
    before logging in. Yugo will never send login credentials over an insecure connection.

    * `:mailbox` - The name of the mailbox to monitor for emails. Defaults to `"INBOX"`.
    The default "INBOX" mailbox is defined in the IMAP standard. If your account has other mailboxes,
    you can pass the name of one as a string. A single [`Client`](`Yugo.Client`) can only monitor a single mailbox -
    to monitor multiple mailboxes, you need to start multiple [`Client`](`Yugo.Client`)s.

  ### Advanced Arguments

    The following options are provided because they can be useful, but in most cases you won't
    need to change them from the default, unless you know what you're doing.

    * `:ssl_verify` - The `:verify` option passed to `:ssl.connect/2`. Can be `:verify_peer` or `:verify_none`.
    Defaults to `:verify_peer`.

  ## Example

  Normally, you do not call this function directly, but rather run it as part of your application's supervision tree.
  See the top of this page for example `Application` usage.
  """
  @spec start_link(
          server: String.t(),
          username: String.t(),
          password: String.t(),
          name: name,
          port: 1..65535,
          tls: boolean,
          ssl_verify: :verify_none | :verify_peer,
          mailbox: String.t()
        ) :: GenServer.on_start()
  def start_link(args) do
    for required <- [:server, :username, :password, :name] do
      Keyword.has_key?(args, required) || raise "Missing required argument `:#{required}`."
    end

    args =
      args
      |> Keyword.put_new(:port, 993)
      |> Keyword.put_new(:tls, true)
      |> Keyword.put_new(:mailbox, "INBOX")
      |> Keyword.put_new(:ssl_verify, :verify_peer)
      |> Keyword.update!(:server, &to_charlist/1)

    args[:ssl_verify] in [:verify_peer, :verify_none] ||
      raise ":ssl_verify option must be one of: :verify_peer, :verify_none"

    name = {:via, Registry, {Yugo.Registry, args[:name]}}
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @common_connect_opts [packet: :line, active: :once, mode: :binary]

  defp ssl_opts(server, ssl_verify),
    do:
      [
        server_name_indication: server,
        verify: ssl_verify,
        cacerts: :public_key.cacerts_get()
      ] ++ @common_connect_opts

  @impl true
  def init(args) do
    {:ok, nil, {:continue, args}}
  end

  @impl true
  def terminate(_reason, conn) do
    conn
    |> send_command("LOGOUT")
  end

  @impl true
  def handle_cast({:subscribe, pid, filter}, conn) do
    conn =
      %{conn | filters: [{filter, pid} | conn.filters]}
      |> update_attrs_needed_by_filters()

    {:noreply, conn}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, conn) do
    conn =
      %{conn | filters: Enum.reject(conn.filters, &(elem(&1, 1) == pid))}
      |> update_attrs_needed_by_filters()

    {:noreply, conn}
  end

  @impl true
  def handle_cast({:fetch, sequence_set}, conn) do
    conn =
      conn
      |> cancel_idle()
      |> queue_fetch_messages(sequence_set)
      |> maybe_idle()

    {:noreply, conn}
  end

  @impl true
  def handle_call({:capabilities}, _from, conn) do
    {:reply, conn.capabilities, conn}
  end

  @impl true
  def handle_call(:count, _from, conn) do
    {:reply, conn.num_exists, conn}
  end

  @impl true
  def handle_call({:move, sequence_set, destination, return_uids}, from, conn) do
    conn =
      conn
      |> cancel_idle()
      |> send_move_command(sequence_set, destination, return_uids, from)

    {:noreply, conn}
  end

  @impl true
  def handle_call({:create, mailbox_name}, from, conn) do
    conn =
      conn
      |> cancel_idle()
      |> send_create_command(mailbox_name, from)

    {:noreply, conn}
  end

  @impl true
  def handle_call({:list, reference, mailbox}, from, conn) do
    conn =
      conn
      |> cancel_idle()
      |> send_command(
        "LIST #{quote_string(reference)} #{quote_string(mailbox)}",
        &on_list_response(&1, &2, &3, from)
      )

    {:noreply, conn}
  end

  defp on_list_response(conn, :ok, response, from) do
    mailbox_names = Enum.map(response, fn %{name: name} -> name end)
    GenServer.reply(from, {:ok, mailbox_names})
    maybe_idle(conn)
  end

  defp send_move_command(conn, sequence_set, destination, return_uids, from) do
    cmd = "MOVE #{sequence_set} #{quote_string(destination)}"
    send_command(conn, cmd, &on_move_response(&1, &2, &3, return_uids, from))
  end

  defp on_move_response(conn, :ok, response, return_uids, from) do
    result = if return_uids, do: Parser.parse_move_uids(response), else: :ok
    GenServer.reply(from, result)
    maybe_idle(conn)
  end

  defp send_create_command(conn, mailbox_name, from) do
    cmd = "CREATE #{quote_string(mailbox_name)}"
    send_command(conn, cmd, &on_create_response(&1, &2, &3, from))
  end

  defp on_create_response(conn, :ok, _text, from) do
    GenServer.reply(from, :ok)
    maybe_idle(conn)
  end

  defp on_create_response(conn, :no, text, from) do
    GenServer.reply(from, {:error, text})
    maybe_idle(conn)
  end

  defp queue_fetch_messages(conn, sequence_set) do
    seqnums = Parser.parse_uid_set(sequence_set)

    new_messages =
      seqnums
      |> Enum.reject(&Map.has_key?(conn.unprocessed_messages, &1))
      |> Map.new(&{&1, %{fetched: nil}})

    %{
      conn
      | unprocessed_messages: Map.merge(conn.unprocessed_messages, new_messages),
        fetch_queue: conn.fetch_queue ++ seqnums
    }
  end

  @impl true
  def handle_continue(args, _state) do
    {:ok, socket} =
      if args[:tls] do
        :ssl.connect(
          args[:server],
          args[:port],
          ssl_opts(args[:server], args[:ssl_verify])
        )
      else
        :gen_tcp.connect(args[:server], args[:port], @common_connect_opts)
      end

    conn = %Conn{
      my_name: args[:name],
      tls: args[:tls],
      socket: socket,
      server: args[:server],
      username: args[:username],
      password: args[:password],
      mailbox: args[:mailbox],
      ssl_verify: args[:ssl_verify]
    }

    {:noreply, conn}
  end

  @impl true
  def handle_info({socket_kind, socket, data}, conn) when socket_kind in [:ssl, :tcp] do
    data = recv_literals(conn, [data])

    # we set [active: :once] each time so that we can parse packets that have synchronizing literals spanning over multiple lines
    :ok =
      if conn.tls do
        :ssl.setopts(socket, active: :once)
      else
        :inet.setopts(socket, active: :once)
      end

    %Conn{} = conn = handle_packet(data, conn)

    {:noreply, conn}
  end

  @impl true
  def handle_info({close_message, _sock}, conn)
      when close_message in [:tcp_closed, :ssl_closed] do
    {:stop, :normal, conn}
  end

  @noop_poll_interval 5000
  @impl true
  def handle_info(:poll_with_noop, conn) do
    Process.send_after(self(), :poll_with_noop, @noop_poll_interval)

    conn =
      if command_in_progress?(conn) do
        conn
      else
        conn
        |> send_command("NOOP")
      end

    {:noreply, conn}
  end

  @idle_timeout 1000 * 60 * 27
  @impl true
  def handle_info(:idle_timeout, conn) do
    conn =
      %{conn | idle_timed_out: true}
      |> cancel_idle()

    {:noreply, conn}
  end

  defp update_attrs_needed_by_filters(conn) do
    attrs =
      [
        Enum.any?(conn.filters, fn {f, _} -> Filter.needs_flags?(f) end) && "FLAGS",
        Enum.any?(conn.filters, fn {f, _} -> Filter.needs_envelope?(f) end) && "ENVELOPE"
      ]
      |> Enum.reject(&(&1 == false))
      |> Enum.join(" ")

    %{conn | attrs_needed_by_filters: attrs}
  end

  # If the previously received line ends with `{123}` (a synchronizing literal), parse more lines until we
  # have at least 123 bytes. If the line ends with another `{123}`, repeat the process.
  defp recv_literals(%Conn{} = conn, [prev | _] = acc, n_remaining \\ 0) do
    if n_remaining <= 0 do
      # n_remaining <= 0 - we don't need any more bytes to fulfil the previous literal. We might be done...
      case Regex.run(~r/\{(\d+)\}\r\n$/, prev, capture: :all_but_first) do
        [n] ->
          # ...unless there is another literal.
          # +2 so that we make sure we get the full command (either the last 2 \r\n, or the next part of the command)
          n = String.to_integer(n) + 2
          recv_literals(conn, acc, n)

        _ ->
          # The last line didn't end with a literal. The packet is complete.
          acc
          |> Enum.reverse()
          |> Enum.join()
      end
    else
      # we need more bytes to complete the current literal. Recv the next line.
      {:ok, next_line} =
        if conn.tls do
          :ssl.recv(conn.socket, 0)
        else
          :gen_tcp.recv(conn.socket, 0)
        end

      recv_literals(conn, [next_line | acc], n_remaining - byte_size(next_line))
    end
  end

  defp handle_packet(data, conn) do
    if conn.got_server_greeting do
      actions = Parser.parse_response(data)

      conn =
        conn
        |> apply_actions(actions)

      conn =
        if conn.idling and conn.unprocessed_messages != %{} do
          conn
          |> cancel_idle()
        else
          conn
        end

      conn
      |> maybe_process_messages()
      |> maybe_idle()
    else
      # ignore the first message from the server, which is the unsolicited greeting
      %{conn | got_server_greeting: true}
      |> send_command("CAPABILITY", &on_unauthed_capability_response/3)
    end
  end

  defp on_unauthed_capability_response(conn, :ok, _text) do
    if !conn.tls do
      if "STARTTLS" in conn.capabilities do
        conn
        |> send_command("STARTTLS", &on_starttls_response/3)
      else
        raise "Server does not support STARTTLS as required by RFC3501."
      end
    else
      conn
      |> do_login()
    end
  end

  defp on_starttls_response(conn, :ok, _text) do
    {:ok, socket} = :ssl.connect(conn.socket, ssl_opts(conn.server, conn.ssl_verify), :infinity)

    %{conn | tls: true, socket: socket}
    |> do_login()
  end

  defp do_login(conn) do
    conn
    |> send_command(
      "LOGIN #{quote_string(conn.username)} #{quote_string(conn.password)}",
      &on_login_response/3
    )
    |> Map.put(:password, "")
  end

  defp on_login_response(conn, :ok, _text) do
    %{conn | state: :authenticated}
    |> send_command("CAPABILITY", &on_authed_capability_response/3)
  end

  defp on_authed_capability_response(conn, :ok, _text) do
    conn
    |> send_command("SELECT #{quote_string(conn.mailbox)}", &on_select_response/3)
  end

  defp on_select_response(conn, :ok, text) do
    conn = %{conn | state: :selected}

    if Regex.match?(~r/^\[READ-ONLY\]/i, text) do
      %{conn | mailbox_mutability: :read_only}
    else
      %{conn | mailbox_mutability: :read_write}
    end
    |> maybe_noop_poll()
  end

  defp command_in_progress?(conn), do: conn.tag_map != %{}

  # starts NOOP polling unless the server supports IDLE
  defp maybe_noop_poll(conn) do
    unless "IDLE" in conn.capabilities do
      send(self(), :poll_with_noop)
    end

    conn
  end

  defp on_idle_response(conn, :ok, _text) do
    if conn.idle_timed_out do
      maybe_idle(conn)
    else
      conn
    end
  end

  # IDLEs if there is no command in progress, we're not already idling, and the server supports IDLE
  defp maybe_idle(conn) do
    if "IDLE" in conn.capabilities and not command_in_progress?(conn) and not conn.idling do
      timer = Process.send_after(self(), :idle_timeout, @idle_timeout)
      conn = %{conn | idling: true, idle_timer: timer, idle_timed_out: false}
      send_command(conn, "IDLE", &on_idle_response/3)
    else
      conn
    end
  end

  defp cancel_idle(conn) do
    if conn.idling do
      Process.cancel_timer(conn.idle_timer)
      send_raw(conn, "DONE\r\n")
      %{conn | idling: false, idle_timer: nil}
    else
      conn
    end
  end

  defp maybe_process_messages(conn) do
    if command_in_progress?(conn) or conn.state != :selected do
      conn
    else
      process_next_message(conn)
    end
  end

  defp process_next_message(conn) do
    cond do
      conn.fetch_queue != [] ->
        [seqnum | rest] = conn.fetch_queue
        conn = %{conn | fetch_queue: rest}
        process_message(conn, seqnum)

      conn.unprocessed_messages != %{} ->
        {seqnum, _} = Enum.min_by(conn.unprocessed_messages, fn {k, _v} -> k end)
        process_message(conn, seqnum)

      true ->
        conn
    end
  end

  defp process_message(conn, seqnum) do
    msg = Map.get(conn.unprocessed_messages, seqnum, %{})

    case msg do
      %{fetched: nil} ->
        conn
        |> fetch_message(seqnum)
        |> maybe_process_messages()

      %{fetched: :filter} ->
        conn
        |> fetch_message_parts(seqnum)
        |> maybe_process_messages()

      %{fetched: :pre_body} ->
        conn
        |> fetch_message_body(seqnum)
        |> maybe_process_messages()

      %{fetched: :full} ->
        conn
        |> release_message(seqnum)
        |> maybe_process_messages()

      _ ->
        conn
        |> fetch_message(seqnum)
        |> maybe_process_messages()
    end
  end

  # defp process_earliest_message(conn) do
  #   {seqnum, msg} = Enum.min_by(conn.unprocessed_messages, fn {k, _v} -> k end)

  #   cond do
  #     not Map.has_key?(msg, :fetched) ->
  #       conn
  #       |> fetch_message(seqnum)
  #       |> maybe_process_messages()

  #     msg.fetched == :filter ->
  #       parts_to_fetch =
  #         [flags: "FLAGS", envelope: "ENVELOPE"]
  #         |> Enum.reject(fn {key, _} -> Map.has_key?(msg, key) end)
  #         |> Enum.map(&elem(&1, 1))

  #       parts_to_fetch = ["BODY" | parts_to_fetch]

  #       conn =
  #         conn
  #         |> put_in([Access.key!(:unprocessed_messages), seqnum, :fetched], :pre_body)

  #       unless Enum.empty?(parts_to_fetch) do
  #         conn
  #         |> send_command("FETCH #{seqnum} (#{Enum.join(parts_to_fetch, " ")})")
  #       else
  #         conn
  #       end

  #     msg.fetched == :pre_body ->
  #       body_parts =
  #         body_part_paths(msg.body_structure)
  #         |> Enum.map(&"BODY.PEEK[#{&1}]")

  #       conn
  #       |> send_command("FETCH #{seqnum} (#{Enum.join(body_parts, " ")})", fn conn, :ok, _text ->
  #         put_in(conn, [Access.key!(:unprocessed_messages), seqnum, :fetched], :full)
  #       end)

  #     msg.fetched == :full ->
  #       conn
  #       |> release_message(seqnum)
  #   end
  # end

  defp body_part_paths(body_structure, path_acc \\ []) do
    case body_structure do
      {:onepart, _body} ->
        path =
          if path_acc == [] do
            "1"
          else
            path_acc
            |> Enum.reverse()
            |> Enum.join(".")
          end

        [path]

      {:multipart, bodies} ->
        bodies
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {b, idx} -> body_part_paths(b, [idx | path_acc]) end)
    end
  end

  # Removes the message from conn.unprocessed_messages and sends it to subscribers with matching filters
  defp release_message(conn, seqnum) do
    {msg, conn} = pop_in(conn, [Access.key!(:unprocessed_messages), seqnum])

    for {filter, pid} <- conn.filters do
      if Filter.accepts?(filter, msg) do
        send(pid, {:email, conn.my_name, package_message(msg, seqnum)})
      end
    end

    conn
  end

  # Preprocesses/cleans the message before it is sent to a subscriber
  defp package_message(msg, seqnum) do
    msg
    |> Map.merge(msg.envelope)
    |> Map.drop([:fetched, :body_structure, :envelope])
    |> Map.put(:body, normalize_structure(msg.body, msg.body_structure))
    |> Map.put(:seqnum, seqnum)
  end

  defp normalize_structure(msg_body, msg_structure) do
    combine_bodies_if_multipart(msg_body)
    |> get_part_structures(msg_structure)
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

  defp get_part_structures({_, content}, {:onepart, map}),
    do: {map.mime_type, map.params, Parser.decode_body(content, map.encoding)}

  defp get_part_structures({[idx | path], content}, {:multipart, parts}),
    do: get_part_structures({path, content}, Enum.at(parts, idx - 1))

  defp get_part_structures(bodies, structure) when is_list(bodies),
    do: Enum.map(bodies, &get_part_structures(&1, structure))

  # FETCHes the message attributes needed to apply filters
  defp fetch_message(conn, seqnum) do
    conn =
      conn
      |> put_in([Access.key!(:unprocessed_messages), seqnum, :fetched], :filter)

    if conn.attrs_needed_by_filters == "" do
      conn
    else
      conn
      |> send_command("FETCH #{seqnum} (#{conn.attrs_needed_by_filters})")
    end
  end

  defp fetch_message_parts(conn, seqnum) do
    parts_to_fetch =
      [flags: "FLAGS", envelope: "ENVELOPE"]
      |> Enum.reject(fn {key, _} -> Map.has_key?(conn.unprocessed_messages[seqnum], key) end)
      |> Enum.map(&elem(&1, 1))

    parts_to_fetch = ["BODY"] ++ parts_to_fetch

    conn =
      conn
      |> put_in([Access.key!(:unprocessed_messages), seqnum, :fetched], :pre_body)

    unless Enum.empty?(parts_to_fetch) do
      conn
      |> send_command("FETCH #{seqnum} (#{Enum.join(parts_to_fetch, " ")})")
    else
      conn
    end
  end

  defp fetch_message_body(conn, seqnum) do
    msg = Map.get(conn.unprocessed_messages, seqnum)

    body_parts =
      body_part_paths(msg.body_structure)
      |> Enum.map(&"BODY.PEEK[#{&1}]")

    conn
    |> send_command("FETCH #{seqnum} (#{Enum.join(body_parts, " ")})", fn conn, :ok, _text ->
      put_in(conn, [Access.key!(:unprocessed_messages), seqnum, :fetched], :full)
    end)
  end

  defp apply_action(conn, action) do
    case action do
      {:capabilities, caps} ->
        %{conn | capabilities: caps}

      {:tagged_response, {tag, status, text}} when status == :ok ->
        {%{on_response: resp_fn, command: command}, conn} =
          pop_in(conn, [Access.key!(:tag_map), tag])

        if String.contains?(command, "LIST") do
          full_response = Enum.reverse(conn.list_response_acc)
          conn = %{conn | list_response_acc: []}
          resp_fn.(conn, status, full_response)
        else
          resp_fn.(conn, status, text)
        end

      {:tagged_response, {tag, status, text}} when status in [:bad, :no] ->
        case {status, text} do
          {:bad, text} ->
            if String.contains?(text, "Expected DONE") do
              # This is likely due to an IDLE command being interrupted
              %{conn | idling: false, idle_timer: nil}
            else
              raise "Got `BAD` response status: `#{text}`. Command that caused this response: `#{conn.tag_map[tag].command}`"
            end

          {:no, text} ->
            if String.contains?(text, "[ALREADYEXISTS] Mailbox already exists") do
              {%{on_response: resp_fn}, conn} = pop_in(conn, [Access.key!(:tag_map), tag])
              resp_fn.(conn, status, text)
            else
              raise "Got `NO` response status: `#{text}`. Command that caused this response: `#{conn.tag_map[tag].command}`"
            end
        end

      :continuation ->
        conn

      {:applicable_flags, flags} ->
        %{conn | applicable_flags: flags}

      {:permanent_flags, flags} ->
        %{conn | permanent_flags: flags}

      {:num_exists, num} ->
        conn =
          if conn.num_exists < num do
            %{
              conn
              | unprocessed_messages:
                  Map.merge(
                    Map.from_keys(Enum.to_list((conn.num_exists + 1)..num), %{}),
                    conn.unprocessed_messages
                  )
            }
          else
            conn
          end

        %{conn | num_exists: num}

      {:num_recent, num} ->
        %{conn | num_recent: num}

      {:first_unseen, num} ->
        %{conn | first_unseen: num}

      {:uid_validity, num} ->
        %{conn | uid_validity: num}

      {:uid_next, num} ->
        %{conn | uid_next: num}

      {:expunge, expunged_num} ->
        %{
          conn
          | num_exists: conn.num_exists - 1,
            unprocessed_messages:
              conn.unprocessed_messages
              |> Enum.reject(fn {k, _v} -> k == expunged_num end)
              |> Enum.map(fn {k, v} ->
                cond do
                  expunged_num < k ->
                    {k - 1, v}

                  expunged_num > k ->
                    {k, v}
                end
              end)
              |> Map.new()
        }

      {:fetch, {seq_num, :flags, flags}} ->
        if Map.has_key?(conn.unprocessed_messages, seq_num) do
          flags = Parser.system_flags_to_atoms(flags)

          conn
          |> put_in([Access.key!(:unprocessed_messages), seq_num, :flags], flags)
        else
          conn
        end

      {:fetch, {seq_num, :envelope, envelope}} ->
        if Map.has_key?(conn.unprocessed_messages, seq_num) do
          conn
          |> put_in([Access.key!(:unprocessed_messages), seq_num, :envelope], envelope)
        else
          conn
        end

      {:fetch, {seq_num, :body, one_or_mpart}} ->
        if Map.has_key?(conn.unprocessed_messages, seq_num) do
          conn
          |> put_in(
            [Access.key!(:unprocessed_messages), seq_num, :body_structure],
            one_or_mpart
          )
        else
          conn
        end

      {:fetch, {seq_num, :body_content, {body_number, content}}} ->
        msg = Map.get(conn.unprocessed_messages, seq_num)

        if msg do
          body =
            case msg.body_structure do
              {:onepart, _} ->
                {body_number, content}

              {:multipart, _} ->
                [{body_number, content} | msg[:body] || []]
            end

          conn
          |> put_in([Access.key!(:unprocessed_messages), seq_num, :body], body)
        else
          conn
        end

      {:fetch, {_seq_num, :uid, _uid}} ->
        conn

      {:list, %{flags: flags, delimiter: delimiter, name: name}} ->
        list_item = %{flags: flags, delimiter: delimiter, name: name}
        %{conn | list_response_acc: [list_item | conn.list_response_acc]}

      {:copyuid,
       %{validity: _validity, source_uids: _source_uids, destination_uids: _destination_uids}} ->
        # might need to save these both off for return to the user, just getting MOVE working first
        conn
    end
  end

  defp apply_actions(conn, []), do: conn

  defp apply_actions(conn, [action | rest]),
    do: conn |> apply_action(action) |> apply_actions(rest)

  defp send_raw(conn, stuff) do
    if conn.tls do
      :ssl.send(conn.socket, stuff)
    else
      :gen_tcp.send(conn.socket, stuff)
    end

    conn
  end

  defp send_command(conn, cmd, on_response \\ fn conn, _status, _text -> conn end) do
    tag = conn.next_cmd_tag
    cmd = "#{tag} #{cmd}\r\n"

    send_raw(conn, cmd)
    |> Map.put(:next_cmd_tag, tag + 1)
    |> put_in([Access.key!(:tag_map), tag], %{command: cmd, on_response: on_response})
  end

  defp quote_string(string) do
    if Regex.match?(~r/[\r\n]/, string) do
      raise "string passed to quote_string contains a CR or LF. TODO: support literals"
    end

    string
    |> String.replace("\\", "\\\\")
    |> String.replace(~S("), ~S(\"))
    |> then(&~s("#{&1}"))
  end
end
