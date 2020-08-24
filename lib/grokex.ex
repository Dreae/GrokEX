defmodule GrokEX do
  @moduledoc """
  Documentation for `GrokEX`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> GrokEX.hello()
      :world

  """
  import Unicode.Guards

  @type grok_predicate :: (String.t() -> :no_match | map())

  @spec compile_predicate(String.t(), %{String.t() => String.t()}) :: {:ok, grok_predicate()} | {:error, term()}
  def compile_predicate(string, patterns) do
    case compile_regex(string, patterns) do
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

  @spec compile_predicate(String.t()) :: {:ok, grok_predicate()} | {:error, term()}
  def compile_predicate(string) do
    compile_predicate(string, %{})
  end

  @spec compile_regex(String.t()) :: {:ok, Regex.t()} | {:error, term()}
  def compile_regex(string) do
    compile_regex(string, %{})
  end

  @spec compile_regex(String.t(), %{String.t() => String.t()}) :: {:ok, Regex.t()} | {:error, term()}
  def compile_regex(string, patterns) do
    patterns = Map.merge(GrokEX.DefaultPatterns.default_patterns(), patterns)
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
