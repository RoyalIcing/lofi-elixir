defmodule Lofi.Parse do
  @moduledoc """
  Parses Lofi content into a structure of text, tags, and mentions.
  """

  @tags_regex ~r/\B#[A-Za-z0-9_-]+(:\s*[^#]*)?/
  @tag_key_value_regex ~r/\B#([a-zA-Z0-9-_]+)(:\s*([^#]*))?/
  @mentions_regex ~r/@([a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9-_]+)*)/
  @introduction_regex ~r/^@([a-zA-Z0-9_-]+):/

  defp clean_text(input) do
    Regex.replace(@tags_regex, input, "")
    |> String.trim
  end

  defp parse_tag_key_value(input) do
    case Regex.run(@tag_key_value_regex, input) do
      [_whole, key] ->
        {key, {:flag, true}}
      [_whole, key, _left, value] ->
        {key, {:content, parse_texts_and_mentions(value)}}
    end
  end

  defp fold_tag_into_list({key, {:flag, true}}, tags_list) do
    [ key | tags_list ]
  end

  defp fold_tag_into_list(_tag, tags_list), do: tags_list

  defp parse_tags(input) do
    pairs = Regex.scan(@tags_regex, input)
    |> Enum.map( fn l ->
      l
      |> List.first
      |> parse_tag_key_value
    end)
    
    tags_path = List.foldr(pairs, [], &fold_tag_into_list/2)
    tags_hash = Map.new(pairs)

    {tags_path, tags_hash}
  end

  defp parse_mention(input) do
    String.slice(input, 1..-1) # Remove leading @
    |> String.split(".")
  end

  defp parse_introduction(input) do
    introduction_indexes = Regex.run(@introduction_regex, input, return: :index, include_captures: true)
    case introduction_indexes do
      nil ->
        { nil, input }
      [_full_range, {start, len}] ->
        {
          String.slice(input, start, len),
          String.slice(input, start+len+1..-1)
          |> String.trim
        }
    end
  end

  defp parse_texts_and_mentions(input) when is_bitstring(input) do
    no_tags_input = clean_text(input)
    texts_and_mentions = Regex.split(@mentions_regex, no_tags_input, include_captures: true)
    process_texts_and_mentions(texts_and_mentions, [], [])
  end

  defp process_texts_and_mentions([ "" ], [], []) do
    %{ texts: [""], mentions: [] }
  end

  defp process_texts_and_mentions([ "" ], texts, mentions) do
    process_texts_and_mentions([], texts, mentions)
  end

  defp process_texts_and_mentions([ text ], texts, mentions) do
    process_texts_and_mentions([], [ text | texts ], mentions)
  end

  defp process_texts_and_mentions([ text | [ mention | rest ] ], texts, mentions) do
    process_texts_and_mentions(rest, [ text | texts ], [ parse_mention(mention) | mentions ])
  end

  defp process_texts_and_mentions([], texts, mentions) do
    %{ texts: Enum.reverse(texts), mentions: Enum.reverse(mentions) }
  end

  @doc """
  Parses Lofi content into a structure of text, tags, and mentions.

  ## Examples

      iex> Lofi.Parse.parse_element("hello")
      %Lofi.Element{ texts: ["hello"], tags_path: [], tags_hash: %{} }

      iex> Lofi.Parse.parse_element("Click me #button")
      %Lofi.Element{ texts: ["Click me"], tags_path: ["button"], tags_hash: %{ "button" => {:flag, true} } }

      iex> Lofi.Parse.parse_element("hello @first-name @last-name")
      %Lofi.Element{ texts: ["hello ", " "], mentions: [["first-name"], ["last-name"]] }

  """
  def parse_element(input) when is_bitstring(input) do
    {introducing, rest} = input
      |> String.trim
      |> parse_introduction

    %{ texts: texts, mentions: mentions } = parse_texts_and_mentions(rest)
    {tags_path, tags_hash} = parse_tags(rest)
    %Lofi.Element{ introducing: introducing, texts: texts, mentions: mentions, tags_path: tags_path, tags_hash: tags_hash }
  end

  # Lines are separated by one newline
  @line_separator_regex ~r/\r\n|\n/
  # Sections are separated by two newlines
  @section_separator_regex ~r/(\r\n|\n){2,}/
  # Nested children have '-' at the start
  @nested_line_regex ~r/^-[\s]*/

  defp split_lines(input) do
    String.split(input, @line_separator_regex, trim: true)
  end

  defp split_sections(input) do
    String.split(input, @section_separator_regex, trim: true)
  end

  defp foldl_section_line_input(input, lines) do
    case Regex.split @nested_line_regex, input do
      # When nested line
      [ "" | [ line_input ] ] ->
        [ parent_element | rest ] = case lines do
          [] ->
            [ %Lofi.Element{} ]
          
          _ ->
            lines
        end
        nested_element = parse_element(line_input)
        updated_parent_element = update_in(parent_element.children, fn children -> [ nested_element | children ] end)
        [ updated_parent_element | rest ]
      
      # When normal line
      [ line_input ] ->
        [ parse_element(line_input) | lines ]
    end
  end

  def parse_section(input) when is_bitstring(input) do
    input
      |> String.trim
      |> split_lines
      |> List.foldl([], &foldl_section_line_input/2)
      # Reverse folded children
      |> Enum.map(fn e -> update_in(e.children, &Enum.reverse/1) end)
      # Reverse folded lines
      |> Enum.reverse
  end

  def parse_sections(input) when is_bitstring(input) do
    input
      |> String.trim
      |> split_sections
      |> Enum.map(&parse_section/1)
  end
end
