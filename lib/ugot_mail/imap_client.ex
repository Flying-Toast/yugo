defmodule UgotMail.IMAPClient do
  @moduledoc """
  A persistent connection to an IMAP server.

  Normally you do not call the functions in this module directly, but rather start an `IMAPClient` as part
  of your application's supervision tree. For example:

      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = [
            {UgotMail.IMAPClient,
             name: :example_client,
             username: "me@example.com",
             password: "pa55w0rd",
             server: "imap.example.com"}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
  """

  use GenServer
  alias UgotMail.Conn
  alias UgotMail.IMAPParser, as: Parser

  @doc """
  Starts an IMAP client process linked to the calling process.

  Takes arguments as a keyword list.

  ## Arguments

    * `:username` - Required. Username used to log in.

    * `:password` - Required. Password used to log in.

    * `:name` - Required. A name used to reference this `IMAPClient`. Can be any atom.

    * `:server` - Required. The location of the IMAP server, e.g. `"imap.example.com"`.

    * `:port` - The port to connect to the server via. Defaults to `993`.

    * `:tls` - Whether or not to connect using TLS. Defaults to `true`.

  ## Example

  Normally, you do not call this function directly, but rather run it as part of your application's supervision tree.
  See the top of this page for example `Application` usage.
  """
  def start_link(args) do
    for required <- [:server, :username, :password, :name] do
      Keyword.has_key?(args, required) || raise "Missing required argument `:#{required}`."
    end

    init_arg =
      args
      |> Keyword.put_new(:port, 993)
      |> Keyword.put_new(:tls, true)
      |> Keyword.update!(:server, &to_charlist/1)

    name = {:via, Registry, {UgotMail.Registry, args[:name]}}
    GenServer.start_link(__MODULE__, init_arg, name: name)
  end

  @impl true
  def init(args) do
    common_connect_opts = [packet: :line, active: :once, mode: :binary]

    {:ok, socket} =
      if args[:tls] do
        :ssl.connect(
          args[:server],
          args[:port],
          [
            server_name_indication: args[:server],
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get()
          ] ++ common_connect_opts
        )
      else
        :gen_tcp.connect(args[:server], args[:port], common_connect_opts)
      end

    conn = %Conn{
      tls: args[:tls],
      socket: socket,
      username: args[:username],
      password: args[:password]
    }

    {:ok, conn}
  end

  @impl true
  def terminate(_reason, _state) do
    IO.puts("TODO: logout on terminate")
  end

  @impl true
  def handle_info({socket_kind, socket, data}, conn) when socket_kind in [:ssl, :tcp] do
    data = recv_literals(conn, [data], 0)

    # we set [active: :once] each time so that we can parse packets that have synchronizing literals
    :ok =
      if conn.tls do
        :ssl.setopts(socket, active: :once)
      else
        :inet.setopts(socket, active: :once)
      end

    %Conn{} = conn = handle_packet(data, conn)

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

      conn
      |> apply_actions(actions)
    else
      # ignore the first message from the server, which is the unsolicited greeting
      %{conn | got_server_greeting: true}
    end
    |> after_packet()
  end

  defp after_packet(conn) do
    cond do
      conn.state == :not_authenticated and conn.login_tag == nil ->
        %{conn | login_tag: conn.next_cmd_tag}
        # TODO: a proper string-quoting function
        |> send_command("LOGIN #{conn.username} \"#{conn.password}\"")
        |> Map.put(:password, "")

      conn.state == :authenticated and conn.capabilities == [] ->
        conn
        |> send_command("CAPABILITY")

      true ->
        IO.inspect("No `after_packet` condition was executed.")
        conn
    end
  end

  defp apply_action(conn, action) do
    case action do
      {:capabilities, caps} ->
        %{conn | capabilities: caps}

      {:tagged_response, {tag, :ok}} when tag == conn.login_tag ->
        %{conn | state: :authenticated}

      {:tagged_response, {tag, :ok}} ->
        IO.puts("TAG #{tag} COMPLETED OK.")
        conn
    end
  end

  defp apply_actions(conn, []), do: conn

  defp apply_actions(conn, [action | rest]),
    do: conn |> apply_action(action) |> apply_actions(rest)

  defp send_command(conn, cmd) do
    cmd = "#{conn.next_cmd_tag} #{cmd}\r\n"

    if conn.tls do
      :ssl.send(conn.socket, cmd)
    else
      :gen_tcp.send(conn.socket, cmd)
    end

    conn
    |> Map.update!(:next_cmd_tag, &(&1 + 1))
  end
end
