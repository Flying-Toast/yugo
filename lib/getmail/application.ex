defmodule Getmail.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Getmail.Registry}
    ]

    opts = [strategy: :one_for_one]
    Supervisor.start_link(children, opts)
  end
end
