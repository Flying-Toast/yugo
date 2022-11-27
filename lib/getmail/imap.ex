defmodule Getmail.IMAP do
  @moduledoc false

  alias Getmail.Conn

  @common_connect_opts [mode: :binary]

  @doc """
  Opens a connection and logs in. Returns a `Getmail.Conn` struct.
  """
  def open(args) do
    args = Keyword.update!(args, :server, &to_charlist/1)

    {:ok, socket} =
      if args[:tls] do
        :ssl.connect(
          args[:server],
          args[:port],
          @common_connect_opts ++
            [
              server_name_indication: args[:server],
              verify: :verify_peer,
              cacerts: :public_key.cacerts_get()
            ]
        )
      else
        :gen_tcp.connect(args[:server], args[:port], @common_connect_opts)
      end

    %Conn{tls: args[:tls], socket: socket}
    |> send_command(~s/LOGIN "#{args[:username]}" "#{args[:password]}"/)
  end

  @doc """
  Logs out of the IMAP connection.
  """
  def close(%Conn{} = conn) do
    send_command(conn, "LOGOUT")

    # We don't need to close the socket here, because this function is called during the GenServer terminate callback, and so the connected gen_tcp socket will be closed automatically.
  end

  @doc """
  Handles a message from the server. Takes the `Getmail.Conn` and message data, and returns the modified conn.
  """
  def handle_message(%Conn{} = conn, data) do
    IO.puts(data)

    conn
  end

  defp send_command(%Conn{} = conn, command) do
    data = "#{conn.next_tag} #{command}\r\n"

    if conn.tls do
      :ok = :ssl.send(conn.socket, data)
    else
      :ok = :gen_tcp.send(conn.socket, data)
    end

    conn
    |> Map.update!(:next_tag, &(&1 + 1))
  end
end
