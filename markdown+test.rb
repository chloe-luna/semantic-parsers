require 'test/unit'

class MarkdownDocumentTest < Test::Unit::TestCase
  
  def setup
    # Helper method to create a new document
    @create_doc = lambda { |text| 
      doc = MarkdownDocument.new(text)
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
  
  # ========================================
  # RENDER TESTS
  # ========================================
  
  def test_render_empty_document
    doc = @create_doc.call("")
    rendered = doc.render
    assert_equal "", rendered
  end
  
  def test_render_yaml_frontmatter
    text = <<-EOF
---
title: Test Document
author: Test Author
---

# Hello World
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('---')
    assert rendered.include?('title: Test Document')
    assert rendered.include?('# Hello World')
  end
  
  def test_render_toml_frontmatter
    text = <<-EOF
+++
title = "Test Document"
+++

Content here
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('+++')
    assert rendered.include?('title = "Test Document"')
    assert rendered.include?('Content here')
  end
  
  def test_render_headings
    text = <<-EOF
# Heading 1
## Heading 2  
### Heading 3
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('# Heading 1')
    assert rendered.include?('## Heading 2')
    assert rendered.include?('### Heading 3')
  end
  
  def test_render_heading_with_nested_content
    text = <<-EOF
# Main Heading

This is nested content.

Another paragraph.
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('# Main Heading')
    assert rendered.include?('This is nested content.')
    assert rendered.include?('Another paragraph.')
  end
  
  def test_render_paragraph
    text = "This is a simple paragraph."
    
    doc = @create_doc.call(text)
    rendered = doc.render
    
    assert_equal text, rendered.strip
  end
  
  def test_render_fenced_code_block
    text = <<-EOF
```ruby
def hello
  puts "world"
end
```
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('```ruby')
    assert rendered.include?('def hello')
    assert rendered.include?('```')
  end
  
  def test_render_indented_code_block
    text = <<-EOF
    def hello
        puts "world"
    end
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    lines = rendered.split("\n")
    assert lines.all? { |line| line.start_with?('    ') }
  end
  
  def test_render_blockquote
    text = <<-EOF
> This is a quote.
> 
> Another line.
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    lines = rendered.split("\n")
    assert lines.all? { |line| line.start_with?('>') }
  end
  
  def test_render_unordered_list
    text = <<-EOF
* Item 1
* Item 2
* Item 3
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('* Item 1')
    assert rendered.include?('* Item 2') 
    assert rendered.include?('* Item 3')
  end
  
  def test_render_ordered_list
    text = <<-EOF
1. First item
2. Second item
3. Third item
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('1. First item')
    assert rendered.include?('2. Second item')
    assert rendered.include?('3. Third item')
  end
  
  def test_render_task_list
    text = <<-EOF
- [x] Completed task
- [ ] Incomplete task
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('- [x] Completed task')
    assert rendered.include?('- [ ] Incomplete task')
  end
  
  def test_render_horizontal_rule
    text = "---"
    
    doc = @create_doc.call(text)
    rendered = doc.render
    
    assert_equal "---", rendered.strip
  end
  
  def test_render_table
    text = <<-EOF
| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('| Header 1 | Header 2 |')
    assert rendered.include?('| Cell 1   | Cell 2   |')
    assert rendered.include?('|----------|----------|')
  end
  
  def test_render_table_with_alignment
    text = <<-EOF
| Left | Center | Right |
|:-----|:------:|------:|
| L1   | C1     | R1    |
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?(':---')
    assert rendered.include?(':---:')
    assert rendered.include?('---:')
  end
  
  def test_render_emphasis
    text = "This has **bold** and *italic* text."
    
    doc = @create_doc.call(text)
    rendered = doc.render
    
    assert rendered.include?('**bold**')
    assert rendered.include?('*italic*')
  end
  
  def test_render_inline_code
    text = "This has `inline code` in it."
    
    doc = @create_doc.call(text)
    rendered = doc.render
    
    assert rendered.include?('`inline code`')
  end
  
  def test_render_links
    text = "Visit [Google](http://google.com) for search."
    
    doc = @create_doc.call(text)
    rendered = doc.render
    
    assert rendered.include?('[Google](http://google.com)')
  end
  
  def test_render_images
    text = "Here's an image: ![Alt text](http://example.com/img.jpg)"
    
    doc = @create_doc.call(text)
    rendered = doc.render
    
    assert rendered.include?('![Alt text](http://example.com/img.jpg)')
  end
  
  def test_render_with_references
    text = <<-EOF
This is a [reference link][ref1].

[ref1]: http://example.com "Example"
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('[reference link][ref1]')
    assert rendered.include?('[ref1]: http://example.com "Example"')
  end
  
  def test_render_with_footnotes
    text = <<-EOF
This has a footnote[^1].

[^1]: This is the footnote content.
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('[^1]:')
    assert rendered.include?('footnote content')
  end
  
  def test_round_trip_simple
    text = <<-EOF
# Hello World

This is a **simple** document with *emphasis*.

## Code Example

```ruby
puts "hello"
```

- Item 1
- Item 2

That's it!
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    # Parse the rendered version
    doc2 = @create_doc.call(rendered)
    
    # Should have same number of blocks
    assert_equal doc.blocks.length, doc2.blocks.length
    
    # Should have same block types
    original_types = doc.blocks.map { |b| b[:type] }
    rendered_types = doc2.blocks.map { |b| b[:type] }
    assert_equal original_types, rendered_types
  end
  
  def test_round_trip_complex
    text = <<-EOF
---
title: Test Document
---

# Main Title

Introduction paragraph.

## Features

- [x] Parsing
- [ ] Rendering  
- [x] Round-trip

> Important note about the implementation.

| Feature | Status |
|---------|--------|
| Parse   | Done   |
| Render  | Done   |

---

Final paragraph[^1].

[^1]: Footnote content here.
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    # Parse the rendered version
    doc2 = @create_doc.call(rendered)
    
    # Should preserve metadata
    assert_not_nil doc2.metadata
    assert_equal 'YAML', doc2.metadata[:type]
    
    # Should preserve footnotes
    assert_equal doc.footnotes.length, doc2.footnotes.length
    
    # Should have same structure
    assert_equal doc.blocks.length, doc2.blocks.length
  end
  
  def test_render_preserves_list_types
    # Test different bullet types
    asterisk_text = "* Asterisk item"
    dash_text = "- Dash item"  
    plus_text = "+ Plus item"
    
    asterisk_doc = @create_doc.call(asterisk_text)
    dash_doc = @create_doc.call(dash_text)
    plus_doc = @create_doc.call(plus_text)
    
    assert asterisk_doc.render.include?('* Asterisk')
    assert dash_doc.render.include?('- Dash')
    assert plus_doc.render.include?('+ Plus')
  end
  
  def test_render_preserves_ordered_list_start
    text = <<-EOF
5. Fifth item
6. Sixth item
EOF
    
    doc = @create_doc.call(text.strip)
    rendered = doc.render
    
    assert rendered.include?('5. Fifth item')
    assert rendered.include?('6. Sixth item')
  end
  
  def test_render_line_breaks
    # Hard break (two spaces + newline)
    text = "Line one  \nLine two"
    
    doc = @create_doc.call(text)
    rendered = doc.render
    
    assert rendered.include?("  \n")
  end

end

# Run the tests
if __FILE__ == $0
  # Simple test runner for Ruby 1.8.7
  test_case = MarkdownDocumentTest.new
  test_methods = test_case.methods.grep(/^test_/)
  
  passed = 0
  failed = 0
  
  puts "Running MarkdownDocument tests..."
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
