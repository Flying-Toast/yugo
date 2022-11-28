defmodule Application do
  def start() do
    children = [
      {Getmail.IMAPClient, name: :my_client, username: "foo@example.com", password: "pa55w0rd", server: "imap.example.com"}
    ]
  end
end

defmodule MailHandler do
  use GenServer

  def init() do
    my_filter = Getmail.Filter.all() # allows all email thru
                |> Getmail.Filter.mailbox("INBOX") # filters down to only messages in inbox
                |> Getmail.Filter.lacks_flag(:seen) # only unseen messages

    Getmail.subscribe(:my_client, my_filter)
  end

  def handle_info({:email, client, message}, state) do
    Getmail.set_flag(client, message, :seen)

    IO.puts("Received an email: #{message.subject}")

    {:noreply, state}
  end
end
