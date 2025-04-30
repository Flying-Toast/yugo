ExUnit.start()

defmodule Helpers.Client do
  import ExUnit.{Assertions, Callbacks}

  def assert_comms(socket, comms) do
    comms =
      ("\n" <> comms)
      |> String.replace(~r/\n$/, "")
      |> String.replace("\n", "\r\n")
      |> String.split(~r/\r\n[CS]:/, trim: true, include_captures: true)
      |> Enum.chunk_every(2)
      |> Enum.map(fn [a, b] -> String.trim(a) <> b <> "\r\n" end)

    assert_comms_aux(socket, comms)
  end

  defp assert_comms_aux(socket, []), do: socket

  defp assert_comms_aux(socket, [line | rest]) do
    module =
      case socket do
        {:sslsocket, _, _} ->
          :ssl

        p when is_port(p) ->
          :gen_tcp
      end

    case line do
      <<"C: ", expected_line::binary>> ->
        case module.recv(socket, 0, 1000) do
          {:ok, received_line} ->
            assert expected_line == received_line

          {:error, :timeout} ->
            raise "Timed out while expecting client message: `#{expected_line}`"
        end

      <<"S: ", line::binary>> ->
        :ok = module.send(socket, line)
    end

    assert_comms_aux(socket, rest)
  end

  def do_hello(socket) do
    socket
    |> assert_comms(~S"""
    S: * OK hello
    C: 0 CAPABILITY
    S: * CAPABILITY IMAP4rev1 AUTH=PLAIN IDLE STARTTLS
    S: 0 ok capability done
    """)
  end

  def do_starttls(socket) do
    socket
    |> assert_comms(~S"""
    C: 1 STARTTLS
    S: 1 OK begin tls handshake...
    """)

    {:ok, socket} =
      :ssl.handshake(
        socket,
        [
          active: false,
          certfile: Path.join(__DIR__, "cert.pem"),
          keyfile: Path.join(__DIR__, "key.pem")
        ],
        1000
      )

    socket
  end

  def do_select_bootstrap(socket, offset \\ 0) do
    assert_comms(
      socket,
      ~s"""
      C: #{offset + 1} LOGIN "foo@example.com" "password 123"
      S: #{offset + 1} OK login done.
      C: #{offset + 2} CAPABILITY
      S: * CAPABILITY IDLE IMAP4rev1
      S: #{offset + 2} OK done
      C: #{offset + 3} SELECT "INBOX"
      S: * FLAGS (\Answered \Flagged \Deleted \Seen \Draft)
      S: * OK [PERMANENTFLAGS (\Answered \Flagged \Deleted \Seen \Draft \*)] Flags permitted.
      S: * 1 EXISTS
      S: * 0 RECENT
      S: * OK [UIDVALIDITY 1669484757] UIDs valid
      S: * OK [UIDNEXT 179] Predicted next UID
      S: * OK [HIGHESTMODSEQ 224] Highest
      S: #{offset + 3} OK [READ-WRITE] selected!!
      C: #{offset + 4} IDLE
      S: + starting idle
      """
    )

    socket
  end

  def accept_gen_tcp() do
    {:ok, listener} = :gen_tcp.listen(0, packet: :line, active: false, mode: :binary)
    {:ok, {_addr, port}} = :inet.sockname(listener)
    name = :crypto.strong_rand_bytes(5)

    opts = [
      username: "foo@example.com",
      password: "password 123",
      name: name,
      server: "localhost",
      port: port,
      tls: false,
      ssl_verify: :verify_none
    ]

    start_link_supervised!({Yugo.Client, opts})
    Yugo.subscribe(name)

    {:ok, socket} = :gen_tcp.accept(listener, 1000)
    on_exit(fn -> :gen_tcp.close(socket) end)

    socket
  end

  defp accept_ssl(name \\ nil) do
    {:ok, listener} =
      :ssl.listen(0,
        packet: :line,
        active: false,
        mode: :binary,
        certfile: Path.join(__DIR__, "cert.pem"),
        keyfile: Path.join(__DIR__, "key.pem")
      )

    {:ok, {_addr, port}} = :ssl.sockname(listener)
    name = name || :crypto.strong_rand_bytes(5)

    opts = [
      username: "foo@example.com",
      password: "password 123",
      name: name,
      server: "localhost",
      port: port,
      tls: true,
      ssl_verify: :verify_none
    ]

    start_link_supervised!({Yugo.Client, opts})
    Yugo.subscribe(name)

    {:ok, socket} = :ssl.transport_accept(listener, 1000)
    {:ok, socket} = :ssl.handshake(socket, 1000)
    on_exit(fn -> :ssl.close(socket) end)

    socket
  end

  def ssl_server(name \\ nil) do
    accept_ssl(name)
    |> do_hello()
    |> do_select_bootstrap()
  end
end
