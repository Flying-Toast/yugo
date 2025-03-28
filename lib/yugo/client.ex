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
  alias Yugo.Message
  alias Yugo.{Conn, Parser, Filter}

  require Logger

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

  @impl GenServer
  def init(args) do
    {:ok, nil, {:continue, {:initialize, args}}}
  end

  @impl GenServer
  def terminate(reason, conn) do
    Logger.info(
      "[#{inspect(__MODULE__)}] [#{inspect(conn.my_name)}] [terminating] #{inspect(reason)}"
    )

    Conn.send_command(conn, :logout)
  end

  @impl GenServer
  def handle_cast({:subscribe, pid, filter}, conn) do
    conn = Conn.subscribe(conn, pid, filter)

    {:noreply, conn}
  end

  def handle_cast({:unsubscribe, pid}, conn) do
    conn = Conn.unsubscribe(conn, pid)

    {:noreply, conn}
  end

  def handle_cast({:command, command, options}, conn) do
    conn = Conn.send_command(conn, command, options)

    {:noreply, conn}
  end

  def command(mailbox_name, command, options \\ []) do
    GenServer.cast({:via, Registry, {Yugo.Registry, mailbox_name}}, {:command, command, options})
  end

  @impl GenServer
  def handle_continue({:initialize, args}, _state) do
    conn = Conn.init(args)
    {:noreply, conn}
  end

  @impl GenServer
  def handle_info({socket_kind, socket, data}, conn) when socket_kind in [:ssl, :tcp] do
    Logger.debug("[#{inspect(__MODULE__)}] [#{socket_kind}] S: #{inspect(data)}")
    data = recv_literals(conn, [data])

    # we set [active: :once] each time so that we can parse packets that have synchronizing literals spanning over multiple lines
    :ok = Conn.set_socket_options(conn, socket, active: :once)

    %Conn{} = conn = handle_packet(data, conn)

    {:noreply, conn}
  end

  def handle_info({close_message, _sock}, conn)
      when close_message in [:tcp_closed, :ssl_closed] do
    {:stop, :normal, conn}
  end

  @noop_poll_interval :timer.seconds(5)
  def handle_info(:poll_with_noop, conn) do
    Process.send_after(self(), :poll_with_noop, @noop_poll_interval)

    conn =
      if Conn.command_in_progress?(conn) do
        conn
      else
        Conn.send_command(conn, :noop)
      end

    {:noreply, conn}
  end

  def handle_info(:idle_timeout, conn) do
    conn = Conn.idle_timed_out(conn)

    {:noreply, conn}
  end

  # If the previously received line ends with `{123}` (a synchronizing literal), parse more lines until we
  # have at least 123 bytes. If the line ends with another `{123}`, repeat the process.
  defp recv_literals(conn, acc, bytes_remaining \\ 0)

  defp recv_literals(%Conn{} = conn, [prev | _] = acc, bytes_remaining)
       when bytes_remaining <= 0 do
    case next_bytes(prev) do
      [next_bytes] ->
        next_bytes = String.to_integer(next_bytes) + 2
        recv_literals(conn, acc, next_bytes)

      _ ->
        acc
        |> Enum.reverse()
        |> Enum.join()
    end
  end

  defp recv_literals(%Conn{} = conn, acc, bytes_remaining) do
    # we need more bytes to complete the current literal. Recv the next line.
    {:ok, next_line} = Conn.recv(conn)

    recv_literals(conn, [next_line | acc], bytes_remaining - byte_size(next_line))
  end

  defp next_bytes(packet) do
    Regex.run(~r/\{(\d+)\}\r\n$/, packet, capture: :all_but_first)
  end

  defp handle_packet(data, %Conn{got_server_greeting: true} = conn) do
    data
    |> Parser.parse_response()
    |> Enum.reduce(conn, &Yugo.Action.apply/2)
    |> maybe_cancel_idle_timer()
    |> maybe_process_messages()
    |> maybe_idle()
  end

  defp handle_packet(_data, %Conn{} = conn) do
    # ignore the first message from the server, which is the unsolicited greeting
    conn
    |> Conn.greet()
    |> Conn.send_command(:capability, on_response: &on_unauthed_capability_response/3)
  end

  defp maybe_cancel_idle_timer(%Conn{} = conn) do
    with %Conn{idling: true, unprocessed_messages: unprocessed_messages}
         when unprocessed_messages != %{} <- conn do
      Conn.cancel_idle_timer(conn)
    end
  end

  defp on_unauthed_capability_response(conn, :ok, _text) do
    cond do
      Conn.using_tls?(conn) ->
        do_login(conn)

      Conn.has_capability?(conn, "STARTTLS") ->
        Conn.send_command(conn, :starttls, on_response: &on_starttls_response/3)

      true ->
        raise "Server does not support STARTTLS as required by RFC3501."
    end
  end

  defp on_starttls_response(conn, :ok, _text) do
    conn
    |> Conn.switch_to_tls()
    |> do_login()
  end

  defp do_login(conn) do
    conn
    |> Conn.send_command({:login, conn.username, conn.password},
      on_response: &on_login_response/3
    )
    |> Conn.clear_password()
  end

  defp on_login_response(conn, :ok, _text) do
    conn
    |> Conn.put_state(:authenticated)
    |> Conn.send_command(:capability, on_response: &on_authed_capability_response/3)
  end

  defp on_authed_capability_response(conn, :ok, _text) do
    Conn.send_command(conn, {:select, conn.mailbox}, on_response: &on_select_response/3)
  end

  defp on_select_response(conn, :ok, text) do
    mailbox_mutability =
      if Regex.match?(~r/^\[READ-ONLY\]/i, text) do
        :read_only
      else
        :read_write
      end

    conn
    |> Conn.put_state(:selected)
    |> Conn.put_mailbox_mutability(mailbox_mutability)
    |> maybe_noop_poll()
  end

  # starts NOOP polling unless the server supports IDLE
  defp maybe_noop_poll(conn) do
    if not Conn.has_capability?(conn, "IDLE") do
      send(self(), :poll_with_noop)
    end

    conn
  end

  defp on_idle_response(%Conn{idle_timed_out: true} = conn, :ok, _text) do
    maybe_idle(conn)
  end

  defp on_idle_response(%Conn{} = conn, :ok, _text) do
    conn
  end

  # IDLEs if there is no command in progress, we're not already idling, and the server supports IDLE
  defp maybe_idle(%Conn{idling: false} = conn) do
    if Conn.has_capability?(conn, "IDLE") and not Conn.command_in_progress?(conn) do
      conn
      |> Conn.set_idling(self())
      |> Conn.send_command(:idle, on_response: &on_idle_response/3)
    else
      conn
    end
  end

  defp maybe_idle(%Conn{} = conn) do
    conn
  end

  defp maybe_process_messages(conn) do
    if Conn.command_in_progress?(conn) or conn.unprocessed_messages == %{} or
         conn.state != :selected do
      conn
    else
      process_earliest_message(conn)
    end
  end

  @parts_to_fetch [flags: "FLAGS", envelope: "ENVELOPE"]
  defp process_earliest_message(conn) do
    {seqnum, msg} = Conn.earliest_unprocessed_message(conn)

    case Map.get(msg, :fetched) do
      nil ->
        conn
        |> fetch_message(seqnum)
        |> maybe_process_messages()

      :filter ->
        parts_to_fetch =
          @parts_to_fetch
          |> Enum.reject(fn {key, _} -> Map.has_key?(msg, key) end)
          |> Enum.map(&elem(&1, 1))

        parts_to_fetch = ["BODY" | parts_to_fetch]

        conn
        |> Conn.map_unprocessed_message(seqnum, %{fetched: :pre_body})
        |> Conn.send_command({:fetch, seqnum, parts_to_fetch})

      :pre_body ->
        body_parts =
          msg.body_structure
          |> body_part_paths()
          |> Enum.map(&"BODY.PEEK[#{&1}]")

        Conn.send_command(conn, {:fetch, seqnum, body_parts},
          on_response: fn conn, :ok, _text ->
            Conn.map_unprocessed_message(conn, seqnum, %{fetched: :full})
          end
        )

      :full ->
        release_message(conn, seqnum)
    end
  end

  defp body_part_paths(body, path_acc \\ [])

  defp body_part_paths({:onepart, _body}, path_acc) do
    path =
      if path_acc == [] do
        "1"
      else
        path_acc
        |> Enum.reverse()
        |> Enum.join(".")
      end

    [path]
  end

  defp body_part_paths({:multipart, bodies}, path_acc) do
    bodies
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {body, index} -> body_part_paths(body, [index | path_acc]) end)
  end

  defp release_message(conn, seqnum) do
    {msg, conn} = Conn.pop_unprocessed_messages(conn, seqnum)

    for {filter, pid} <- conn.filters do
      if Filter.accepts?(filter, msg) do
        send(pid, {:email, conn.my_name, Message.package(msg)})
      end
    end

    conn
  end

  defp fetch_message(conn, seqnum) do
    conn = Conn.map_unprocessed_message(conn, seqnum, %{fetched: :filter})

    case Conn.filter_attributes(conn) do
      [] ->
        conn

      filter_attributes ->
        Conn.send_command(conn, {:fetch, seqnum, filter_attributes})
    end
  end
end
