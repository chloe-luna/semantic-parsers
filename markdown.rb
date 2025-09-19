# Example usage:
# doc = Markdown.new(markdown_text)
# doc.solve
# puts doc.blocks.inspect

require 'test/unit'

class Markdown
  attr_reader :blocks, :references, :footnotes, :metadata
  
  def initialize(text)
    @text = text
    @blocks = []
    @references = {}
    @footnotes = {}
    @metadata = nil
    @lines = []
    @current_line = 0
  end
  
  def solve
    @lines = @text.split(/\r?\n/)
    @current_line = 0
    
    # Parse frontmatter first
    parse_frontmatter
    
    # Parse reference definitions and footnotes
    extract_references_and_footnotes
    
    # Parse blocks
    while @current_line < @lines.length
      block = parse_block
      @blocks << block if block
    end
    
    self
  end
  
  private
  
  def parse_frontmatter
    return unless @current_line < @lines.length
    
    line = @lines[@current_line]
    if line == '---' || line == '+++'
      delimiter = line
      format_type = line == '---' ? 'YAML' : 'TOML'
      @current_line += 1
      content_lines = []
      
      while @current_line < @lines.length && @lines[@current_line] != delimiter
        content_lines << @lines[@current_line]
        @current_line += 1
      end
      
      if @current_line < @lines.length && @lines[@current_line] == delimiter
        @metadata = {
          :type => format_type,
          :content => content_lines.join("\n")
        }
        @current_line += 1
        skip_blank_lines
      end
    end
  end
  
  def extract_references_and_footnotes
    i = 0
    while i < @lines.length
      line = @lines[i]
      
      # Link/image reference: [ref]: url "title"
      if line =~ /^\s*\[([^\]]+)\]:\s*(\S+)(?:\s+"([^"]*)")?/
        ref_name = $1
        url = $2
        title = $3
        @references[ref_name] = {
          :url => url,
          :title => title
        }
        @lines[i] = '' # Remove from main parsing
      # Footnote definition: [^ref]: content
      elsif line =~ /^\s*\[\^([^\]]+)\]:\s*(.*)$/
        footnote_ref = $1
        content = $2
        footnote_lines = [content]
        
        # Collect continuation lines
        j = i + 1
        while j < @lines.length && (@lines[j] =~ /^\s{4,}/ || @lines[j] =~ /^\s*$/)
          if @lines[j] =~ /^\s{4,}/
            footnote_lines << @lines[j][4..-1] # Remove 4-space indent
            @lines[j] = '' # Remove from main parsing
          else
            footnote_lines << @lines[j]
          end
          j += 1
        end
        
        @footnotes[footnote_ref] = footnote_lines.join("\n")
        @lines[i] = '' # Remove from main parsing
      end
      i += 1
    end
  end
  
  def parse_block
    skip_blank_lines
    return nil if @current_line >= @lines.length
    
    line = @lines[@current_line]
    
    # Horizontal rule
    if line =~ /^(\*{3,}|-{3,}|_{3,})\s*$/
      @current_line += 1
      return { :type => 'horizontal_rule' }
    end
    
    # Heading
    if line =~ /^(#{1,6})\s+(.+)$/
      level = $1.length
      content = $2.strip
      @current_line += 1
      
      # Check for nested content under heading
      nested_blocks = parse_nested_blocks_for_heading(level)
      
      return {
        :type => 'heading',
        :level => level,
        :content => parse_inline(content),
        :nested_blocks => nested_blocks
      }
    end
    
    # Fenced code block
    if line =~ /^```(.*)$/ || line =~ /^~~~(.*)$/
      fence = line[0,3]
      language = $1.strip
      language = nil if language.empty?
      @current_line += 1
      
      code_lines = []
      while @current_line < @lines.length && !@lines[@current_line].start_with?(fence)
        code_lines << @lines[@current_line]
        @current_line += 1
      end
      
      @current_line += 1 if @current_line < @lines.length # Skip closing fence
      
      return {
        :type => 'code_block',
        :subtype => 'fenced',
        :language => language,
        :content => code_lines.join("\n")
      }
    end
    
    # Indented code block
    if line =~ /^    (.*)$/
      code_lines = []
      while @current_line < @lines.length && (@lines[@current_line] =~ /^    (.*)$/ || @lines[@current_line] =~ /^\s*$/)
        if @lines[@current_line] =~ /^    (.*)$/
          code_lines << $1
        else
          code_lines << ''
        end
        @current_line += 1
      end
      
      return {
        :type => 'code_block',
        :subtype => 'indented',
        :content => code_lines.join("\n").rstrip
      }
    end
    
    # Blockquote
    if line =~ /^>\s?(.*)$/
      quote_lines = []
      while @current_line < @lines.length && @lines[@current_line] =~ /^>\s?(.*)$/
        quote_lines << $1
        @current_line += 1
      end
      
      # Parse the quoted content as blocks
      quoted_text = quote_lines.join("\n")
      nested_parser = Markdown.new(quoted_text)
      nested_parser.solve
      
      return {
        :type => 'blockquote',
        :blocks => nested_parser.blocks
      }
    end
    
    # List (ordered or unordered)
    if line =~ /^(\s*)([*+-]|\d+\.)\s+(.*)$/
      return parse_list
    end
    
    # Table (simple detection)
    if line.include?('|') && peek_next_line && peek_next_line.include?('|')
      return parse_table
    end
    
    # Paragraph (default)
    parse_paragraph
  end
  
  def parse_nested_blocks_for_heading(heading_level)
    nested_blocks = []
    
    # Look ahead to see if there's content that should be nested under this heading
    while @current_line < @lines.length
      next_line = @lines[@current_line]
      
      # Stop if we hit another heading of same or higher level
      if next_line =~ /^(#{1,#{heading_level}})\s+/
        break
      end
      
      # Skip blank lines
      if next_line =~ /^\s*$/
        @current_line += 1
        next
      end
      
      # Parse the next block as nested content
      block = parse_block
      nested_blocks << block if block
    end
    
    nested_blocks
  end
  
  def parse_list
    list_items = []
    list_type = nil
    indent_level = 0
    
    while @current_line < @lines.length
      line = @lines[@current_line]
      
      if line =~ /^(\s*)([*+-]|\d+\.)\s+(.*)$/
        current_indent = $1.length
        marker = $2
        content = $3
        
        # Determine list type from first item
        if list_type.nil?
          if marker =~ /\d+\./
            list_type = { :type => 'ordered', :start => marker.to_i }
          else
            bullet_type = case marker
              when '*' then 'asterisk'
              when '-' then 'dash'
              when '+' then 'plus'
            end
            list_type = { :type => 'unordered', :bullet => bullet_type }
          end
          indent_level = current_indent
        end
        
        # If indent level changes significantly, this might be a nested list
        # For simplicity, we'll handle basic nesting
        if current_indent == indent_level
          @current_line += 1
          
          # Check for task list
          task_status = nil
          if content =~ /^\[([x ])\]\s*(.*)$/i
            task_status = $1.downcase == 'x' ? 'completed' : 'incomplete'
            content = $2
          end
          
          # Collect continuation lines and nested blocks
          item_content = [content]
          nested_blocks = []
          
          while @current_line < @lines.length
            next_line = @lines[@current_line]
            
            # Check if this is another list item or end of list
            if next_line =~ /^(\s*)([*+-]|\d+\.)\s+/
              next_indent = $1.length
              if next_indent <= indent_level
                break # This is the next item at same or higher level
              end
            end
            
            # Continuation line (indented more than marker)
            if next_line =~ /^#{' ' * (indent_level + 2)}(.*)$/
              item_content << $1
              @current_line += 1
            # Blank line in list
            elsif next_line =~ /^\s*$/
              @current_line += 1
            else
              break
            end
          end
          
          list_items << {
            :content => parse_inline(item_content.join("\n")),
            :nested_blocks => nested_blocks,
            :task_status => task_status
          }
        else
          break
        end
      else
        break
      end
    end
    
    {
      :type => 'list',
      :list_type => list_type,
      :items => list_items
    }
  end
  
  def parse_table
    rows = []
    
    # Parse header row
    header_line = @lines[@current_line]
    @current_line += 1
    
    # Parse alignment row
    alignment_line = @lines[@current_line] if @current_line < @lines.length
    @current_line += 1
    
    alignments = []
    if alignment_line && alignment_line =~ /^[\s|:-]+$/
      alignment_line.split('|').each do |cell|
        cell = cell.strip
        if cell.start_with?(':') && cell.end_with?(':')
          alignments << 'center'
        elsif cell.end_with?(':')
          alignments << 'right'
        elsif cell.start_with?(':')
          alignments << 'left'
        else
          alignments << 'default'
        end
      end
    end
    
    # Parse header
    header_cells = header_line.split('|').map { |cell| cell.strip }.reject { |cell| cell.empty? }
    header = {
      :cells => header_cells.each_with_index.map { |content, i|
        {
          :content => parse_inline(content),
          :alignment => alignments[i] || 'default'
        }
      }
    }
    
    # Parse data rows
    while @current_line < @lines.length && @lines[@current_line].include?('|')
      row_line = @lines[@current_line]
      @current_line += 1
      
      cells = row_line.split('|').map { |cell| cell.strip }.reject { |cell| cell.empty? }
      rows << {
        :cells => cells.each_with_index.map { |content, i|
          {
            :content => parse_inline(content),
            :alignment => alignments[i] || 'default'
          }
        }
      }
    end
    
    {
      :type => 'table',
      :header => header,
      :rows => rows
    }
  end
  
  def parse_paragraph
    para_lines = []
    
    while @current_line < @lines.length
      line = @lines[@current_line]
      
      # Stop on blank line
      break if line =~ /^\s*$/
      
      # Stop on other block elements
      break if line =~ /^(#{1,6}\s|```|~~~|>\s?|\s*([*+-]|\d+\.)\s+|\*{3,}|-{3,}|_{3,})/
      
      para_lines << line
      @current_line += 1
    end
    
    return nil if para_lines.empty?
    
    {
      :type => 'paragraph',
      :content => parse_inline(para_lines.join("\n"))
    }
  end
  
  def parse_inline(text)
    return [] if text.nil? || text.empty?
    
    # This is a simplified inline parser
    # In a full implementation, you'd want a more sophisticated approach
    
    result = []
    remaining = text
    
    while !remaining.empty?
      # Code spans `code`
      if remaining =~ /^`([^`]+)`(.*)$/
        result << { :type => 'code', :content => $1 }
        remaining = $2
      # Strong **text** or __text__
      elsif remaining =~ /^(\*\*|__)([^*_]+)\1(.*)$/
        result << { 
          :type => 'emphasis', 
          :emphasis_type => 'strong',
          :content => parse_inline($2)
        }
        remaining = $3
      # Italic *text* or _text_
      elsif remaining =~ /^(\*|_)([^*_]+)\1(.*)$/
        result << { 
          :type => 'emphasis', 
          :emphasis_type => 'italic',
          :content => parse_inline($2)
        }
        remaining = $3
      # Links [text](url) or [text](url "title")
      elsif remaining =~ /^\[([^\]]+)\]\(([^)]+?)(?:\s+"([^"]*)")?\)(.*)$/
        link_text = $1
        url = $2
        title = $3
        result << {
          :type => 'link',
          :content => parse_inline(link_text),
          :target => { :type => 'direct', :url => url },
          :title => title
        }
        remaining = $4
      # Reference links [text][ref]
      elsif remaining =~ /^\[([^\]]+)\]\[([^\]]*)\](.*)$/
        link_text = $1
        ref = $2.empty? ? link_text : $2
        result << {
          :type => 'link',
          :content => parse_inline(link_text),
          :target => { :type => 'reference', :ref => ref },
          :title => nil
        }
        remaining = $3
      # Images ![alt](url) or ![alt](url "title")
      elsif remaining =~ /^!\[([^\]]*)\]\(([^)]+?)(?:\s+"([^"]*)")?\)(.*)$/
        alt_text = $1
        url = $2
        title = $3
        result << {
          :type => 'image',
          :content => parse_inline(alt_text),
          :target => { :type => 'direct', :url => url },
          :title => title
        }
        remaining = $4
      # Line breaks (two spaces + newline)
      elsif remaining =~ /^  \n(.*)$/m
        result << { :type => 'line_break' }
        remaining = $1
      # Soft breaks (single newline)
      elsif remaining =~ /^\n(.*)$/m
        result << { :type => 'soft_break' }
        remaining = $1
      # Regular text
      else
        if remaining =~ /^([^*_`!\[\n]+)(.*)$/m
          result << { :type => 'text', :content => $1 }
          remaining = $2
        else
          # Single character
          result << { :type => 'text', :content => remaining[0,1] }
          remaining = remaining[1..-1] || ''
        end
      end
    end
    
    result
  end
  
  def skip_blank_lines
    while @current_line < @lines.length && @lines[@current_line] =~ /^\s*$/
      @current_line += 1
    end
  end
  
  def peek_next_line
    idx = @current_line + 1
    idx < @lines.length ? @lines[idx] : nil
  end
end

class MarkdownTest < Test::Unit::TestCase
  
  def setup
    # Helper method to create a new document
    @create_doc = lambda { |text| 
      doc = Markdown.new(text)
      doc.solve
      doc
    }
  end
  
  def test_empty_document
    doc = @create_doc.call("")
    assert_equal [], doc.blocks
    assert_equal({}, doc.references)
    assert_equal({}, doc.footnotes)
    assert_nil doc.metadata
  end
  
  def test_yaml_frontmatter
    text = <<-EOF
---
title: Test Document
author: Test Author
---

# Hello World
EOF
    
    doc = @create_doc.call(text)
    
    assert_not_nil doc.metadata
    assert_equal 'YAML', doc.metadata[:type]
    assert doc.metadata[:content].include?('title: Test Document')
    assert doc.metadata[:content].include?('author: Test Author')
    
    # Should still parse the heading
    assert_equal 1, doc.blocks.length
    assert_equal 'heading', doc.blocks[0][:type]
  end
  
  def test_toml_frontmatter
    text = <<-EOF
+++
title = "Test Document"
author = "Test Author"
+++

Content here
EOF
    
    doc = @create_doc.call(text)
    
    assert_not_nil doc.metadata
    assert_equal 'TOML', doc.metadata[:type]
    assert doc.metadata[:content].include?('title = "Test Document"')
  end
  
  def test_headings
    text = <<-EOF
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 6, doc.blocks.length
    
    (1..6).each do |i|
      block = doc.blocks[i-1]
      assert_equal 'heading', block[:type]
      assert_equal i, block[:level]
      assert_equal "Heading #{i}", block[:content][0][:content]
    end
  end
  
  def test_heading_with_nested_content
    text = <<-EOF
# Main Heading

This is a paragraph under the heading.

Another paragraph.

## Sub Heading

This should be separate.
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 2, doc.blocks.length
    
    main_heading = doc.blocks[0]
    assert_equal 'heading', main_heading[:type]
    assert_equal 1, main_heading[:level]
    assert_equal 2, main_heading[:nested_blocks].length
    
    # Check nested paragraphs
    assert_equal 'paragraph', main_heading[:nested_blocks][0][:type]
    assert_equal 'paragraph', main_heading[:nested_blocks][1][:type]
    
    # Second heading should be separate
    sub_heading = doc.blocks[1]
    assert_equal 'heading', sub_heading[:type]
    assert_equal 2, sub_heading[:level]
  end
  
  def test_paragraphs
    text = <<-EOF
This is a simple paragraph.

This is another paragraph
with a line break in the middle.
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 2, doc.blocks.length
    
    assert_equal 'paragraph', doc.blocks[0][:type]
    assert_equal 'paragraph', doc.blocks[1][:type]
    
    # First paragraph should have simple text
    first_para = doc.blocks[0][:content]
    assert_equal 1, first_para.length
    assert_equal 'text', first_para[0][:type]
    assert_equal 'This is a simple paragraph.', first_para[0][:content]
  end
  
  def test_fenced_code_block
    text = <<-EOF
```ruby
def hello
  puts "world"
end
```

~~~python
print("hello world")
~~~
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 2, doc.blocks.length
    
    # Ruby code block
    ruby_block = doc.blocks[0]
    assert_equal 'code_block', ruby_block[:type]
    assert_equal 'fenced', ruby_block[:subtype]
    assert_equal 'ruby', ruby_block[:language]
    assert ruby_block[:content].include?('def hello')
    
    # Python code block
    python_block = doc.blocks[1]
    assert_equal 'code_block', python_block[:type]
    assert_equal 'fenced', python_block[:subtype]
    assert_equal 'python', python_block[:language]
    assert ruby_block[:content].include?('print("hello world")')
  end
  
  def test_indented_code_block
    text = <<-EOF
    def indented_code
        return "hello"
    end

Regular paragraph here.
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 2, doc.blocks.length
    
    code_block = doc.blocks[0]
    assert_equal 'code_block', code_block[:type]
    assert_equal 'indented', code_block[:subtype]
    assert code_block[:content].include?('def indented_code')
    
    paragraph = doc.blocks[1]
    assert_equal 'paragraph', paragraph[:type]
  end
  
  def test_blockquote
    text = <<-EOF
> This is a quote.
> 
> With multiple paragraphs.
>
> > And nested quotes.
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 1, doc.blocks.length
    
    quote = doc.blocks[0]
    assert_equal 'blockquote', quote[:type]
    assert quote[:blocks].length > 0
    
    # Should have parsed nested content
    nested_blocks = quote[:blocks]
    assert nested_blocks.any? { |block| block[:type] == 'paragraph' }
  end
  
  def test_unordered_list
    text = <<-EOF
* Item 1
* Item 2
  * Nested item
* Item 3

- Dash list
- Another item

+ Plus list
+ Another item
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 3, doc.blocks.length
    
    # Asterisk list
    asterisk_list = doc.blocks[0]
    assert_equal 'list', asterisk_list[:type]
    assert_equal 'unordered', asterisk_list[:list_type][:type]
    assert_equal 'asterisk', asterisk_list[:list_type][:bullet]
    assert_equal 3, asterisk_list[:items].length
    
    # Dash list
    dash_list = doc.blocks[1]
    assert_equal 'list', dash_list[:type]
    assert_equal 'dash', dash_list[:list_type][:bullet]
    
    # Plus list
    plus_list = doc.blocks[2]
    assert_equal 'list', plus_list[:type]
    assert_equal 'plus', plus_list[:list_type][:bullet]
  end
  
  def test_ordered_list
    text = <<-EOF
1. First item
2. Second item
3. Third item

5. Starting at five
6. Next item
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 2, doc.blocks.length
    
    first_list = doc.blocks[0]
    assert_equal 'list', first_list[:type]
    assert_equal 'ordered', first_list[:list_type][:type]
    assert_equal 1, first_list[:list_type][:start]
    
    second_list = doc.blocks[1]
    assert_equal 'ordered', second_list[:list_type][:type]
    assert_equal 5, second_list[:list_type][:start]
  end
  
  def test_task_list
    text = <<-EOF
- [x] Completed task
- [ ] Incomplete task
- [X] Another completed task
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 1, doc.blocks.length
    
    task_list = doc.blocks[0]
    assert_equal 'list', task_list[:type]
    
    items = task_list[:items]
    assert_equal 3, items.length
    
    assert_equal 'completed', items[0][:task_status]
    assert_equal 'incomplete', items[1][:task_status]
    assert_equal 'completed', items[2][:task_status]
  end
  
  def test_horizontal_rule
    text = <<-EOF
---

***

___
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 3, doc.blocks.length
    
    doc.blocks.each do |block|
      assert_equal 'horizontal_rule', block[:type]
    end
  end
  
  def test_table
    text = <<-EOF
| Header 1 | Header 2 | Header 3 |
|----------|:--------:|---------:|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 1, doc.blocks.length
    
    table = doc.blocks[0]
    assert_equal 'table', table[:type]
    
    # Check header
    header = table[:header]
    assert_equal 3, header[:cells].length
    assert_equal 'default', header[:cells][0][:alignment]
    assert_equal 'center', header[:cells][1][:alignment]
    assert_equal 'right', header[:cells][2][:alignment]
    
    # Check rows
    assert_equal 2, table[:rows].length
    assert_equal 3, table[:rows][0][:cells].length
  end
  
  def test_inline_emphasis
    text = "This has **bold** and *italic* and ***both*** text."
    
    doc = @create_doc.call(text)
    
    assert_equal 1, doc.blocks.length
    
    paragraph = doc.blocks[0]
    content = paragraph[:content]
    
    # Should have mixed text and emphasis elements
    emphasis_elements = content.select { |elem| elem[:type] == 'emphasis' }
    assert emphasis_elements.length >= 2
    
    # Check for strong emphasis
    strong_elem = emphasis_elements.find { |elem| elem[:emphasis_type] == 'strong' }
    assert_not_nil strong_elem
  end
  
  def test_inline_code
    text = "This has `inline code` in it."
    
    doc = @create_doc.call(text)
    
    paragraph = doc.blocks[0]
    content = paragraph[:content]
    
    code_elem = content.find { |elem| elem[:type] == 'code' }
    assert_not_nil code_elem
    assert_equal 'inline code', code_elem[:content]
  end
  
  def test_links
    text = <<-EOF
This is a [direct link](http://example.com) and this is a [reference link][ref].

Also an [implicit reference link] and a [titled link](http://example.com "Title").
EOF
    
    doc = @create_doc.call(text)
    
    paragraph = doc.blocks[0]
    content = paragraph[:content]
    
    links = content.select { |elem| elem[:type] == 'link' }
    assert links.length >= 3
    
    # Check direct link
    direct_link = links.find { |link| link[:target][:type] == 'direct' }
    assert_not_nil direct_link
    assert_equal 'http://example.com', direct_link[:target][:url]
    
    # Check reference link
    ref_link = links.find { |link| link[:target][:type] == 'reference' }
    assert_not_nil ref_link
  end
  
  def test_images
    text = "This has an ![image](http://example.com/img.jpg) in it."
    
    doc = @create_doc.call(text)
    
    paragraph = doc.blocks[0]
    content = paragraph[:content]
    
    image = content.find { |elem| elem[:type] == 'image' }
    assert_not_nil image
    assert_equal 'http://example.com/img.jpg', image[:target][:url]
  end
  
  def test_reference_definitions
    text = <<-EOF
This is a [reference link][ref1] and an ![image][img1].

[ref1]: http://example.com "Link Title"
[img1]: http://example.com/image.jpg "Image Title"
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 2, doc.references.length
    
    ref1 = doc.references['ref1']
    assert_not_nil ref1
    assert_equal 'http://example.com', ref1[:url]
    assert_equal 'Link Title', ref1[:title]
    
    img1 = doc.references['img1']
    assert_not_nil img1
    assert_equal 'http://example.com/image.jpg', img1[:url]
  end
  
  def test_footnotes
    text = <<-EOF
This has a footnote[^1] and another[^note].

[^1]: This is the first footnote.

[^note]: This is a longer footnote.
    With multiple lines.
    And more content.
EOF
    
    doc = @create_doc.call(text)
    
    assert_equal 2, doc.footnotes.length
    
    footnote1 = doc.footnotes['1']
    assert_not_nil footnote1
    assert footnote1.include?('first footnote')
    
    note_footnote = doc.footnotes['note']
    assert_not_nil note_footnote
    assert note_footnote.include?('longer footnote')
    assert note_footnote.include?('multiple lines')
  end
  
  def test_mixed_content_document
    text = <<-EOF
---
title: Complex Document
---

# Main Title

This is an introduction paragraph with **bold** text and a [link](http://example.com).

## Code Examples

Here's some Ruby code:

```ruby
def hello(name)
  puts "Hello, #{name}!"
end
```

## Lists and Quotes

Some bullet points:

* First point
* Second point with `inline code`
* Third point

> This is an important quote.
> It spans multiple lines.

## Table

| Feature | Supported | Notes |
|---------|:---------:|-------|
| Headers | Yes | All levels |
| Lists | Yes | Ordered and unordered |
| Code | Yes | Fenced and indented |

---

That's all for now[^1].

[^1]: This is a footnote.
EOF
    
    doc = @create_doc.call(text)
    
    # Should have frontmatter
    assert_not_nil doc.metadata
    assert_equal 'YAML', doc.metadata[:type]
    
    # Should have footnote
    assert_equal 1, doc.footnotes.length
    assert_not_nil doc.footnotes['1']
    
    # Should have multiple blocks
    assert doc.blocks.length > 5
    
    # Should have different block types
    block_types = doc.blocks.map { |block| block[:type] }
    assert block_types.include?('heading')
    assert block_types.include?('paragraph')
    assert block_types.include?('code_block')
    assert block_types.include?('list')
    assert block_types.include?('blockquote')
    assert block_types.include?('table')
    assert block_types.include?('horizontal_rule')
  end
  
  def test_line_breaks
    text = "Line one  \nLine two\nLine three"
    
    doc = @create_doc.call(text)
    
    paragraph = doc.blocks[0]
    content = paragraph[:content]
    
    # Should have line break and soft break elements
    breaks = content.select { |elem| elem[:type] == 'line_break' || elem[:type] == 'soft_break' }
    assert breaks.length >= 1
  end

end

# Run the tests
if __FILE__ == $0
  # Simple test runner for Ruby 1.8.7
  test_case = MarkdownTest.new
  test_methods = test_case.methods.grep(/^test_/)
  
  passed = 0
  failed = 0
  
  puts "Running Markdown tests..."
  puts "=" * 50
  
  test_methods.each do |method_name|
    begin
      test_case.setup
      test_case.send(method_name)
      puts "✓ #{method_name}"
      passed += 1
    rescue Exception => e
      puts "✗ #{method_name}: #{e.message}"
      failed += 1
    end
  end
  
  puts "=" * 50
  puts "Tests completed: #{passed} passed, #{failed} failed"
  
  if failed > 0
    exit 1
  else
    puts "All tests passed!"
    exit 0
  end
end
