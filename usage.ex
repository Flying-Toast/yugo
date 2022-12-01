defmodule Application do
  def start() do
    children = [
      {Yugo.Client, name: :my_client, username: "foo@example.com", password: "pa55w0rd", server: "imap.example.com"}
    ]
  end
end

defmodule MailHandler do
  use GenServer

  def init() do
    my_filter = Yugo.Filter.all() # allows all email thru
                |> Yugo.Filter.lacks_flag(:seen) # only unseen messages

    Yugo.subscribe(:my_client, my_filter)
  end

  def handle_info({:email, client, message}, state) do
    Yugo.set_flag(client, message, :seen)

    IO.puts("Received an email: #{message.subject}")

    {:noreply, state}
  end
end
