defmodule Yugo.SSLServer do
  @moduledoc false

  use GenServer

  def start_link(listener) do
    GenServer.start_link(__MODULE__, listener)
  end

  @impl true
  def init(listener) do
    send(self(), :accept)
    {:ok, {listener, nil}}
  end

  @impl true
  def handle_info(:accept, {listener, _}) do
    {:ok, socket} = :ssl.transport_accept(listener, 1000)
    {:ok, socket} = :ssl.handshake(socket, 1000)
    {:noreply, {listener, socket}}
  end

  @impl true
  def handle_call(:get_socket, _from, {listener, socket}) do
    {:reply, socket, {listener, socket}}
  end
end
