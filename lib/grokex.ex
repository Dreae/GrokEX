defmodule GrokEX do
  @moduledoc """
  Compiles grok patterns into Elixir objects which can be used for testing
  strings against patterns.

  ## Examples
  ```
  iex> GrokEX.compile_regex("Here's a number %{NUMBER:the_number}")
  {:ok,
    ~r/Here's a number (?<the_number>(?:(?<![0-9.+-])(?>[+-]?(?:(?:[0-9]+(?:\\.[0-9]+)?)|(?:\\.[0-9]+)))))/}

  iex> GrokEX.compile_predicate("User %{QUOTEDSTRING:username} connected from %{IP:user_address}")
  #Function<0.46228848/1 in GrokEX.compile_predicate/2>
  ```
  """

  import Unicode.Guards

  @type grok_predicate :: (String.t() -> :no_match | map())
  @type compile_opts :: {:patterns, %{String.t() => String.t()}}

  @doc """
  Compiles a grok pattern to a function that takes a string and returns either the
  named captures if the string matches the pattern, or `:no_match` if the string
  doesn't match.

  ## Examples

  ```
  iex> GrokEX.compile_predicate("User %{QUOTEDSTRING:username} connected from %{IP:user_address}")
  ```

  ## Options
    * `:patterns` - Provide custom patterns to the grok compiler. These patterns will be merged with
      the default patterns
  """
  @spec compile_predicate(String.t(), [compile_opts()]) :: {:ok, grok_predicate()} | {:error, term()}
  def compile_predicate(string, opts \\ []) do
    patterns = Keyword.get(opts, :patterns, %{}) |> Map.merge(GrokEX.DefaultPatterns.default_patterns())
    case compile_regex(string, [patterns: patterns]) do
      {:ok, regex} ->
        fn string ->
          if Regex.match?(regex, string) do
            Regex.named_captures(regex, string)
          else
            :no_match
          end
        end
      err -> err
    end
  end

  @spec compile_regex(String.t(), [compile_opts()]) :: {:ok, Regex.t()} | {:error, term()}
  @doc """
  Compiles a grok pattern to a function that takes a string and returns either the
  named captures if the string matches the pattern, or `:no_match` if the string
  doesn't match.

  ## Examples

  ```
  iex> GrokEX.compile_regex("User %{QUOTEDSTRING:username} connected from %{IP:user_address}")
  ```

  ## Options
    * `:patterns` - Provide custom patterns to the grok compiler. These patterns will be merged with
      the default patterns
  """
  def compile_regex(string, opts \\ []) do
    patterns = Keyword.get(opts, :patterns, %{}) |> Map.merge(GrokEX.DefaultPatterns.default_patterns())
    with {:ok, pattern} <- compile_pattern([], string, patterns),
         {:ok, regex} <- Regex.compile(pattern)
    do
      {:ok, regex}
    else
      err -> err
    end
  end

  defp tokenize("", tokens, column, current_string) do
    {:ok, Enum.reverse([finalize_string_literal(current_string, column) | tokens])}
  end
  defp tokenize(<<"%", remaining::binary>>, tokens, column, current_string) do
    case remaining do
      "" -> {:error, [:unexpected_eof, column]}
      <<"{", remaining::binary>> -> consume_template_type(remaining, [finalize_string_literal(current_string, column) | tokens], column + 1, "")
      <<codepoint::utf8, remaining::binary>> -> tokenize(remaining, tokens, column + 1, current_string <> <<codepoint::utf8>>)
    end
  end
  defp tokenize(<<codepoint::utf8, remaining::binary>>, tokens, column, current_string), do: tokenize(remaining, tokens, column + 1, current_string <> <<codepoint::utf8>>)

  defp finalize_string_literal(string, column), do: [:literal_string, column - String.length(string), string]

  defp consume_template_type(<<"}", remaining::binary>>, tokens, column, type) do
    tokenize(remaining, [finalize_type(type, column) | tokens], column + 1, "")
  end
  defp consume_template_type(<<":", remaining::binary>>, tokens, column, type) do
    consume_template_name(remaining, [finalize_type(type, column) | tokens], column + 1, "")
  end
  defp consume_template_type(<<codepoint::utf8, remaining::binary>>, tokens, column, "") when is_upper(codepoint) do
    consume_template_type(remaining, tokens, column + 1, <<codepoint::utf8>>)
  end
  defp consume_template_type(<<codepoint::utf8, remaining::binary>>, tokens, column, type) when is_upper(codepoint) or is_digit(codepoint) do
    consume_template_type(remaining, tokens, column + 1, type <> <<codepoint::utf8>>)
  end
  defp consume_template_type(<<codepoint::utf8, _remaining::binary>>, _tokens, column, _type) do
    {:error, [:unexpected_token, :template_type, column, <<codepoint::utf8>>, [:upper, :digit]]}
  end

  defp finalize_type(type, column), do: [:template_type, column - String.length(type), type]

  defp consume_template_name(<<codepoint::utf8, remaining::binary>>, tokens, column, "") when is_lower(codepoint) or is_upper(codepoint) do
    consume_template_name(remaining, tokens, column + 1, <<codepoint::utf8>>)
  end
  defp consume_template_name(<<codepoint::utf8, remaining::binary>>, tokens, column, name) when is_lower(codepoint) or is_upper(codepoint) or is_digit(codepoint) or codepoint == ?_ do
    consume_template_name(remaining, tokens, column + 1, name <> <<codepoint::utf8>>)
  end
  defp consume_template_name(<<"}", remaining::binary>>, tokens, column, name) do
    tokenize(remaining, [[:template_param, column - String.length(name), name] | tokens], column, "")
  end
  defp consume_template_name(<<t::utf8, _remaining::binary>>, _tokens, column, _name), do: {:error, [:unexpected_token, :template_param, column, <<t::utf8>>, [:alphanumeric]]}
  defp consume_template_name("", _tokens, column, _name), do: {:error, [:unexpected_eof, column]}

  defp compile_pattern([[:literal_string, _column, string]], "", _patterns), do: {:ok, string}
  defp compile_pattern([[:literal_string, _column, string] | tokens], pattern, patterns), do: compile_pattern(tokens, "#{pattern}#{string}", patterns)
  defp compile_pattern([[:template_type, column, type] | tokens], pattern, patterns) do
    case patterns do
      %{^type => type_pattern} ->
        case tokens do
          [[:template_param, _column, name] | tokens] -> compile_pattern(tokens, "#{pattern}(?<#{name}>#{type_pattern})", patterns)
          [_token | _tokens] -> compile_pattern(tokens, "#{pattern}#{type_pattern}", patterns)
          [] -> {:error, [:unexpected_eof, -1]}
        end
      _ -> {:error, [:unknown_pattern, column - String.length(type), type]}
    end
  end

  defp compile_pattern([], pattern, patterns) do
    case tokenize(pattern, [], 0, "") do
      {:ok, tokens} -> compile_pattern(tokens, "", patterns)
      err -> err
    end
  end
end
