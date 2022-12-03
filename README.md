# Yugo

Yugo is an easy and high-level IMAP client library for Elixir.


To begin, start a `Yugo.Client` as part of your application's supervision tree:
```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Yugo.Client,
       name: :example_client,
       server: "imap.example.com",
       username: "me@example.com",
       password: "pa55w0rd"}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Now you can call `Yugo.subscribe/2` to have your process receive messages whenever a new email arrives that matches the provided `Yugo.Filter`:

```elixir
# filter to only notify us about messages containing "hello" or "goodbye" in the subject:
my_filter =
  Yugo.Filter.all()
  |> Yugo.Filter.subject_matches(~r/(hello|goodbye)/)

# By subscribing, our process will be notified about all future emails that match the filter.
Yugo.subscribe(:example_client, my_filter)

receive do
  {:email, client, message} ->
    Yugo.set_flag(client, message, :seen)
    IO.puts("Received an email with subject `#{message.subject}`")
end
```
