defmodule Yugo.Transport.Ssl do
  @behaviour Yugo.Transport

  alias Yugo.Transport.Ssl, as: SslTransport

  defstruct [:server, :port, :verify]

  def connect_to_socket(%SslTransport{} = transport, socket) do
    :ssl.connect(socket, connect_options(transport), :infinity)
  end

  @impl Yugo.Transport
  def init(args) do
    %SslTransport{
      server: args[:server],
      port: args[:port],
      verify: args[:ssl_verify]
    }
  end

  @impl Yugo.Transport
  def connect(%SslTransport{port: port, server: server} = transport) do
    :ssl.connect(server, port, connect_options(transport))
  end

  @impl Yugo.Transport
  def send(socket, command) do
    :ssl.send(socket, command)
  end

  @impl Yugo.Transport
  def recv(socket, length) do
    :ssl.recv(socket, length)
  end

  @impl Yugo.Transport
  def set_socket_options(socket, options) do
    :ssl.setopts(socket, options)
  end

  @common_options Yugo.Transport.common_connection_options()

  defp connect_options(%SslTransport{server: server, verify: verify}) do
    [
      {:server_name_indication, server},
      {:verify, verify},
      {:cacerts, :public_key.cacerts_get()}
      | @common_options
    ]
  end
end
