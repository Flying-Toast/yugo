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
             # NOTE: You should not hardcode passwords like this example.
             # In production, you should probably store/access your password as an environment variable.
             password: "pa55w0rd"}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
  """

  use GenServer
  alias Yugo.{Conn, Parser}

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
          mailbox: String.t(),
          server: String.t()
        ) :: GenServer.on_start()
  def start_link(args) do
    for required <- [:server, :username, :password, :name] do
      Keyword.has_key?(args, required) || raise "Missing required argument `:#{required}`."
    end

    init_arg =
      args
      |> Keyword.put_new(:port, 993)
      |> Keyword.put_new(:tls, true)
      |> Keyword.put_new(:mailbox, "INBOX")
      |> Keyword.update!(:server, &to_charlist/1)

    name = {:via, Registry, {Yugo.Registry, args[:name]}}
    GenServer.start_link(__MODULE__, init_arg, name: name)
  end

  @common_connect_opts [packet: :line, active: :once, mode: :binary]

  defp ssl_opts(server),
    do:
      [
        server_name_indication: server,
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get()
      ] ++ @common_connect_opts

  @impl true
  def init(args) do
    {:ok, socket} =
      if args[:tls] do
        :ssl.connect(
          args[:server],
          args[:port],
          ssl_opts(args[:server])
        )
      else
        :gen_tcp.connect(args[:server], args[:port], @common_connect_opts)
      end

    conn = %Conn{
      tls: args[:tls],
      socket: socket,
      server: args[:server],
      username: args[:username],
      password: args[:password],
      mailbox: args[:mailbox]
    }

    {:ok, conn}
  end

  @impl true
  def terminate(_reason, conn) do
    conn
    |> send_command("LOGOUT")
  end

  @impl true
  def handle_cast({:subscribe, pid, filter}, conn) do
    {:noreply, %{conn | filters: [{filter, pid} | conn.filters]}}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, conn) do
    conn = %{conn | filters: Enum.reject(conn.filters, &(elem(&1, 1) == pid))}

    {:noreply, conn}
  end

  @impl true
  def handle_info({socket_kind, socket, data}, conn) when socket_kind in [:ssl, :tcp] do
    data = recv_literals(conn, [data], 0)

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

  # If the previously received line ends with `{123}` (a synchronizing literal), parse more lines until we
  # have at least 123 bytes. If the line ends with another `{123}`, repeat the process.
  defp recv_literals(%Conn{} = conn, [prev | _] = acc, n_remaining) do
    if n_remaining <= 0 do
      # n_remaining <= 0 - we don't need any more bytes to fulfil the previous literal. We might be done...
      case Regex.run(~r/\{(\d+)\}\r\n$/, prev, capture: :all_but_first) do
        [n] ->
          # ...unless there is another literal.
          n = String.to_integer(n)
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

      recv_literals(conn, [next_line | acc], n_remaining - String.length(next_line))
    end
  end

  defp handle_packet(data, conn) do
    if conn.got_server_greeting do
      actions = Parser.parse_response(data)

      conn =
        if conn.idling and actions != [:continuation] do
          conn
          |> cancel_idle()
        else
          conn
        end

      conn =
        conn
        |> apply_actions(actions)

      if conn.unprocessed_messages == %{} do
        conn
        |> maybe_idle()
      else
        conn
        |> process_messages()
      end
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
    {:ok, socket} = :ssl.connect(conn.socket, ssl_opts(conn.server), :infinity)

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

      %{conn | idling: true, idle_timer: timer, idle_timed_out: false}
      |> send_command("IDLE", &on_idle_response/3)
    else
      conn
    end
  end

  defp cancel_idle(conn) do
    Process.cancel_timer(conn.idle_timer)

    %{conn | idling: false, idle_timer: nil}
    |> send_raw("DONE\r\n")
  end

  defp process_messages(conn) do
    IO.puts("We need to process these messages: #{inspect(conn.unprocessed_messages)}")
    conn
  end

  defp apply_action(conn, action) do
    case action do
      {:capabilities, caps} ->
        %{conn | capabilities: caps}

      {:tagged_response, {tag, status, text}} when status == :ok ->
        {%{on_response: resp_fn}, conn} = pop_in(conn, [Access.key!(:tag_map), tag])

        resp_fn.(conn, status, text)

      {:tagged_response, {tag, status, text}} when status in [:bad, :no] ->
        raise "Got `#{status |> to_string() |> String.upcase()}` response status: `#{text}`. Command that caused this response: `#{conn.tag_map[tag].command}`"

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

      {:expunge, _seq_num} ->
        %{
          conn
          | num_exists: conn.num_exists - 1,
            unprocessed_messages:
              Enum.map(conn.unprocessed_messages, fn {k, v} -> {k - 1, v} end)
              |> Map.new()
        }
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
