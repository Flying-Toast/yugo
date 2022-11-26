defmodule Getmail.IMAP do
  @moduledoc false

  alias Getmail.Conn

  @doc """
  Opens a connection and logs in. Returns a `Getmail.Conn` struct.
  """
  def open(args) do
    {:ok, socket} =
      if args[:tls] do
        :ssl.connect(args[:server], args[:port],
          server_name_indication: args[:server],
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get()
        )
      else
        :gen_tcp.connect(args[:server], args[:port], [])
      end

    IO.puts("TODO: IMAP login")

    %Getmail.Conn{tls: args[:tls], socket: socket}
  end

  @doc """
  Logs out and closes the connection.
  """
  def close(%Conn{} = conn) do
    IO.puts "TODO: IMAP logout"

    if conn.tls do
      :ok = :ssl.close(conn.socket)
    end
    :ok = :gen_tcp.close(conn.socket)
  end

  @doc """
  Handles a message from the server. Takes the `Getmail.Conn` and message data, and returns the modified conn.
  """
  def handle_reply(%Conn{} = conn, data) do
    IO.puts(data)

    conn
  end
end
