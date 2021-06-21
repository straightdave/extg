defmodule Extg.MixProject do
  use Mix.Project

  def project do
    [
      app: :extg,
      version: "0.1.1",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: desc()
    ]
  end

  defp package do
    [
      name: "extg",
      files: ~w(lib .formatter.exs mix.exs README*),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/straightdave/extg"}
    ]
  end

  defp desc do
    """
    Test Group that expects all to succeed or fail fast due to one fails.
    """
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
