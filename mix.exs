defmodule GrokEX.MixProject do
  use Mix.Project

  def project do
    [
      app: :grokex,
      version: "0.2.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:unicode_guards, "~> 0.3.1"},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Dreae/grokex"}
    ]
  end

  defp description do
    "A library for parsing grok patterns into regular expressions"
  end
end
