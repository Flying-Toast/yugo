defmodule Getmail.MixProject do
  use Mix.Project

  def project do
    [
      app: :getmail,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Getmail",
      source_url: "https://github.com/Flying-Toast/getmail",
      homepage_url: "https://github.com/Flying-Toast/getmail",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {Getmail.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end
end
