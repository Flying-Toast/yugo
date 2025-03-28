defmodule Yugo.MixProject do
  use Mix.Project

  def project do
    [
      app: :yugo,
      version: "1.0.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Yugo is an easy and high-level IMAP client library.",
      package: package(),
      name: "Yugo",
      source_url: "https://github.com/Flying-Toast/yugo",
      compilers: [:leex, :yecc] ++ Mix.compilers(),
      docs: [
        source_ref: "master",
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {Yugo.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Flying-Toast/yugo"}
    ]
  end
end
