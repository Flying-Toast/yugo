defmodule Yugo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Yugo.Registry}
    ]

    opts = [strategy: :one_for_one]
    Supervisor.start_link(children, opts)
  end
end
