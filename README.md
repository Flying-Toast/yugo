# Getmail

An IMAP library for Elixir.

# Example

```elixir
defmodule MyApp.MailHandler do
  use Getmail, server: "mail.example.com", username: "me@example.com", password: "secret"

  def handle_email(TODO) do
    TODO
  end
end
```
