defmodule Yugo do
  @moduledoc """
  Auxiliary functions for Yugo.
  """

  alias Yugo.{Filter, Client}

  @typedoc """
  The first field is the name associated with the address, and the second field is the address itself.

  e.g. `{"Bart", "bart@simpsons.family"}`
  """
  @type address :: {nil | String.t(), String.t()}

  @typedoc """
  e.g. `"text/html"`, `"image/png"`, `"text/plain"`, etc.

  For more, see this [list of MIME types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types).
  """
  @type mime_type :: String.t()

  @typedoc """
  A body can be either "onepart" or "multipart".

  A "onepart" body is a tuple in the form `{mime_type, params, content}`, where `mime_type` is a [`mime_type`](`t:mime_type/0`),
  `params` is a string->string map, and `content` is a [`binary`](`t:binary/0`).

  A "multipart" body consists of a *list* of [`body`s](`t:body/0`), which can themselves be either onepart or multipart.
  """
  @type body :: {mime_type, %{optional(String.t()) => String.t()}, binary} | [body]

  @type flag :: :seen | :answered | :flagged | :draft | :deleted

  @typedoc """
  An email message sent to a subscribed process.

  # Difference between `sender` and `from`
  Both "sender" and "from" are fields used by IMAP to indicate the origin of the email.
  They are *usually* the same, but they can be different and they have different meanings:
  - `from` - the author who physically wrote the email. `From` is typically the address you see when viewing the message in an email client.
  - `sender` - the person who sent the email, potentially different than `from` if someone else sent the email on behalf of the author.
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
          from: [address],
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

  @spec list(Client.name(), reference :: String.t(), mailbox :: String.t()) :: [
          {:name, String.t()} | {:delimiter, String.t()} | {:attributes, [String.t()]}
        ]
  def list(client_name, reference \\ "", mailbox \\ "%") do
    GenServer.call({:via, Registry, {Yugo.Registry, client_name}}, {:list, reference, mailbox})
  end

  @spec capabilities(Client.name()) :: [String.t()]
  def capabilities(client_name) do
    GenServer.call({:via, Registry, {Yugo.Registry, client_name}}, {:capabilities})
  end

  @spec has_capability?(Client.name(), String.t()) :: Bool.t()
  def has_capability?(client_name, capability) do
    capabilities(client_name)
    |> Enum.any?(fn cap -> cap == capability end)
  end
end
