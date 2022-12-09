defmodule Yugo do
  @moduledoc """
  Auxiliary functions for Yugo.
  """

  alias Yugo.{Filter, Client}

  @type address :: String.t()

  @typedoc """
  e.g. `"text/html"`, `"image/png"`, `"text/plain"`, etc.

  For more, see this [list of MIME types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types).
  """
  @type mime_type :: String.t()

  @typedoc """
  A body can be either "onepart" or "multipart".

  A "onepart" body is a tuple in the form `{mime_type, params, content}`, where `mime_type` is a [`mime_type`](`t:mime_type/0`),
  `params` is a string->string map, and `content` is a [`binary`](`t:binary/0`).

  A "multipart" body consists of a list of "parts". Each part is itself another [`body`](`t:body/0`).
  """
  @type body :: {mime_type, %{String.t() => String.t()}, binary} | [body]

  @type flag :: :seen | :answered | :flagged | :draft | :deleted

  @typedoc """
  An email message sent to a subscribed process.
  """
  @type email :: %{
          bcc: [address],
          body: body,
          cc: [address],
          date: DateTime.t(),
          flags: [flag],
          in_reply_to: nil | String.t(),
          message_id: nil | String.t(),
          reply_to: [address],
          sender: [address],
          subject: nil | String.t(),
          to: [address]
        }

  @doc """
  Subscribes the calling process to the [`Client`](`Yugo.Client`) named by `client_name`.

  When you subscribe to a client, your process will be notified about new emails via a message
  in the form `{:email, client, message}`, where `client` is the name of the client that is notifying you,
  and `message` is the email. See the [`email`](`t:Yugo.email/0`) type for the structure of the `message` field.

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
