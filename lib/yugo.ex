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
  @spec subscribe(Client.name(), Filter.t()) :: :ok | {:error, :invalid_client_name}
  def subscribe(client_name, filter \\ Filter.all()) do
    case Registry.lookup(Yugo.Registry, client_name) do
      [{_, pid}] ->
        GenServer.cast(pid, {:subscribe, self(), filter})

      [] ->
        {:error, :invalid_client_name}
    end
  end

  @doc """
  Unsubscribes the calling process from the specified [`Client`](`Yugo.Client).

  This will unsubscribe the calling process from all messages from the client,
  regardless of how many separate times you [`subscribe`d](`subscribe/2`)
  """
  @spec unsubscribe(Client.name()) :: :ok | {:error, :invalid_client_name}
  def unsubscribe(client_name) do
    case Registry.lookup(Yugo.Registry, client_name) do
      [{_, pid}] ->
        GenServer.cast(pid, {:unsubscribe, self()})

      [] ->
        {:error, :invalid_client_name}
    end
  end
end
