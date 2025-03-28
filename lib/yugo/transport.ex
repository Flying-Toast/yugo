defmodule Yugo.Transport do
  alias Yugo.Transport.Ssl, as: SslTransport
  alias Yugo.Transport.Tcp, as: TcpTransport

  @type socket :: :inet.socket()
  @type command :: String.t()
  @type packet :: String.t() | binary() | term()

  @callback init(Keyword.t()) :: struct()
  @callback connect(struct()) :: {:ok, socket()} | {:error, term()}
  @callback send(socket(), command()) :: :ok | {:error, term()}
  @callback recv(socket(), non_neg_integer()) :: {:ok, packet()} | {:error, term()}
  @callback set_socket_options(socket(), Keyword.t()) :: :ok | {:error, term()}

  @common_connect_opts [packet: :line, active: :once, mode: :binary]

  def common_connection_options do
    @common_connect_opts
  end

  def init(args) do
    if args[:tls] do
      SslTransport.init(args)
    else
      TcpTransport.init(args)
    end
  end

  def connect(%transport{} = transport_config) do
    transport.connect(transport_config)
  end

  def send(%transport{}, socket, command) do
    transport.send(socket, command)
  end

  def recv(%transport{}, socket, length) do
    transport.recv(socket, length)
  end

  def set_socket_options(%transport{}, socket, options) do
    transport.set_socket_options(socket, options)
  end
end
