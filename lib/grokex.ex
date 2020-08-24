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

  @spec compile_predicate(String.t()) :: {:ok, grok_predicate()} | {:error, term()}

  def compile_predicate(string) do
    with {:ok, tokens} <- tokenize(string, [], 0, ""),
         {:ok, pattern} <- compile_pattern(tokens, ""),
         {:ok, regex} <- Regex.compile(pattern)
    do
      fn string ->
        if Regex.match?(regex, string) do
          Regex.named_captures(regex, string)
        else
          :no_match
        end
      end
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

  defp consume_template_type(<<":", remaining::binary>>, tokens, column, type) do
    case finalize_type(type, column) do
      {:ok, type} ->
        consume_template_name(remaining, [type | tokens], column + 1, "")
        error -> error
    end
  end

  defp consume_template_type(<<codepoint::utf8, remaining::binary>>, tokens, column, "") when is_upper(codepoint) do
    consume_template_type(remaining, tokens, column + 1, <<codepoint::utf8>>)
  end
  defp consume_template_type(<<codepoint::utf8, remaining::binary>>, tokens, column, type) when is_upper(codepoint) or is_digit(codepoint) do
    consume_template_type(remaining, tokens, column + 1, type <> <<codepoint::utf8>>)
  end

  defp finalize_type(type, column), do: {:ok, [:template_type, column - String.length(type), type]}

  defp consume_template_name(<<codepoint::utf8, remaining::binary>>, tokens, column, "") when is_lower(codepoint) or is_upper(codepoint) do
    consume_template_name(remaining, tokens, column + 1, <<codepoint::utf8>>)
  end
  defp consume_template_name(<<codepoint::utf8, remaining::binary>>, tokens, column, name) when is_lower(codepoint) or is_upper(codepoint) or is_digit(codepoint) do
    consume_template_name(remaining, tokens, column + 1, name <> <<codepoint::utf8>>)
  end
  defp consume_template_name(<<"}", remaining::binary>>, tokens, column, name) do
    tokenize(remaining, [[:template_param, column - String.length(name), name] | tokens], column, "")
  end
  defp consume_template_name(<<t::utf8, _remaining::binary>>, _tokens, column, name), do: {:error, [:unexpected_char, :template_param, column, t, name]}
  defp consume_template_name("", _tokens, column, _name), do: {:error, [:unexpected_eof, column]}

  defp compile_pattern([[:literal_string, _column, string] | tokens], pattern), do: compile_pattern(tokens, "#{pattern}#{string}")
  defp compile_pattern([[:template_type, _column, "NUMBER"] | tokens], pattern) do
    case tokens do
      [[:template_param, _column, name] | tokens] -> compile_pattern(tokens, "#{pattern}(?<#{name}>[0-9]+)")
      [[token, column | _rest] | _tokens] -> {:error, [:unexpected_token, token, column]}
      [] -> {:error, [:unexpected_eof, -1]}
    end
  end
  defp compile_pattern([[:template_type, column, type] | _tokens], _pattern) do
    {:error, [:unknown_pattern, column - String.length(type), type]}
  end

  defp compile_pattern([], pattern), do: {:ok, pattern}
end
