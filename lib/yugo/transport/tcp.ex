defmodule Yugo.Transport.Tcp do
  @behaviour Yugo.Transport

  defstruct [:server, :port]

  alias Yugo.Transport.Tcp, as: TcpTransport

  @common_options Yugo.Transport.common_connection_options()

  @impl Yugo.Transport
  def init(args) do
    %TcpTransport{
      server: args[:server],
      port: args[:port]
    }
  end

  @impl Yugo.Transport
  def connect(%TcpTransport{port: port, server: server}) do
    :gen_tcp.connect(server, port, @common_options)
  end

  @impl Yugo.Transport
  def send(socket, command) do
    :gen_tcp.send(socket, command)
  end

  @impl Yugo.Transport
  def recv(socket, length) do
    :gen_tcp.recv(socket, length)
  end

  @impl Yugo.Transport
  def set_socket_options(socket, options) do
    :inet.setopts(socket, options)
  end
end
