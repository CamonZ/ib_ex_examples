defmodule IbExExamples.MixProject do
  use Mix.Project

  def project do
    [
      app: :ib_ex_examples,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:timex, "~> 3.7"},
      {:owl, "~> 0.12"},
      {:ib_ex, git: "https://github.com/camonz/ib_ex.git"}
    ]
  end
end
