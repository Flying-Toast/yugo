defmodule Getmail.IMAPClient do
  @moduledoc """
  A persistent connection to an IMAP server.

  Normally you do not call the functions in this module directly, but rather start an `IMAPClient` as part
  of your application's supervision tree. For example:

      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = [
            {Getmail.IMAPClient,
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
  alias Getmail.Conn

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

    name = {:via, Registry, {Getmail.Registry, args[:name]}}
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

    IO.puts("TODO: login on init")

    conn = %Conn{tls: args[:tls], socket: socket}
    {:ok, conn}
  end

  @impl true
  def terminate(_reason, _state) do
    IO.puts("TODO: logout on terminate")
  end

  @impl true
  def handle_info({socket_kind, socket, data}, conn) when socket_kind in [:ssl, :tcp] do
    # detect a synchonizing literal and parse the required number of bytes
    data =
      case Regex.run(~r/\{(\d+)\}\r\n$/, data, capture: :all_but_first) do
        [n] ->
          # add 2 to account for the final \r\n
          n = String.to_integer(n) + 2
          packet_lines = [data | recv_n_bytes(conn, n)]
          Enum.join(packet_lines)

        _ ->
          data
      end

    # we set [active: :once] each time so that we can parse packets that have synchronizing literals (see above)
    :ok =
      if conn.tls do
        :ssl.setopts(socket, active: :once)
      else
        :inet.setopts(socket, active: :once)
      end

    conn = handle_packet(data, conn)

    {:noreply, conn}
  end

  defp recv_n_bytes(%Conn{} = conn, n, acc \\ []) do
    if n > 0 do
      {:ok, next_line} =
        if conn.tls do
          :ssl.recv(conn.socket, 0)
        else
          :gen_tcp.recv(conn.socket, 0)
        end

      recv_n_bytes(conn, n - String.length(next_line), [next_line | acc])
    else
      Enum.reverse(acc)
    end
  end

  defp handle_packet(data, conn) do
    IO.puts("GOT PACKET: ...#{data}...")

    conn
  end
end
