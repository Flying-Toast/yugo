defmodule Yugo.GenTCPServer do
  @moduledoc false

  use GenServer

  def start_link({listener, pid}) do
    GenServer.start_link(__MODULE__, {listener, pid})
  end

  @impl true
  def init({listener, pid}) do
    send(self(), {:accept, pid})
    {:ok, {listener, nil}}
  end

  @impl true
  def handle_info({:accept, pid}, {listener, _}) do
    {:ok, socket} = :gen_tcp.accept(listener, 1000)
    :gen_tcp.controlling_process(socket, pid)

    {:noreply, {listener, socket}}
  end

  @impl true
  def handle_call(:get_socket, _from, {listener, socket}) do
    {:reply, socket, {listener, socket}}
  end
end
