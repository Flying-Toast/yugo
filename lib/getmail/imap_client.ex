defmodule Getmail.IMAPClient do
  @moduledoc """
  A persistent connection to an IMAP server.
  """

  use GenServer
  alias Getmail.Conn

  def start_link(opts) do
    for required <- [:server, :username, :password, :name] do
      Keyword.has_key?(opts, required) || raise "Missing required argument `:#{required}`."
    end

    init_arg =
      opts
      |> Keyword.put_new(:port, 993)
      |> Keyword.put_new(:tls, true)

    name = {:via, Registry, {Getmail.Registry, opts[:name]}}
    GenServer.start_link(__MODULE__, init_arg, name)
  end

  @impl true
  def init(args) do
    common_connect_opts = [packet: :line]

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
end
