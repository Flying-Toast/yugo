defmodule Yugo do
  @moduledoc """
  Auxiliary functions for Yugo.
  """

  alias Yugo.{Filter, Client}

  @doc """
  Subscribes the calling process to the [`Client`](`Yugo.Client`) named by `client_name`.

  When you subscribe to a client, your process will be notified about new emails via a message
  in the form `{:email, client, message}`, where `client` is the name of the client that is notifying you,
  and `message` is the email.

  You may also pass an optional [`Filter`](`Yugo.Filter`) as the second argument to match what
  emails you want to be notified about. If you do not pass a filter, it defaults to [`Filter.all`](`Yugo.Filter.all/0`),
  which allows all emails to pass through.
  """
  @spec subscribe(Client.name(), Filter.t()) :: :ok
  def subscribe(client_name, filter \\ Filter.all()) do
    GenServer.cast({:via, Registry, {Yugo.Registry, client_name}}, {:subscribe, self(), filter})
  end

  @doc """
  Unsubscribes the calling process from the specified [`Client`](`Yugo.Client`).

  This will unsubscribe the calling process from all messages from the client,
  regardless of how many separate times you [`subscribe`d](`subscribe/2`)
  """
  @spec unsubscribe(Client.name()) :: :ok
  def unsubscribe(client_name) do
    GenServer.cast({:via, Registry, {Yugo.Registry, client_name}}, {:unsubscribe, self()})
  end
end
