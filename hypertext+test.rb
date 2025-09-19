require 'test/unit'

class HypertextTest < Test::Unit::TestCase
  
  def setup
    # Helper method to create a new hypertext document
    @create_doc = lambda { |html| 
      doc = Hypertext.new(html)
      doc.solve
      doc
    }
  end
  
  def test_empty_document
    doc = @create_doc.call("")
    assert_equal [], doc.body
    assert_nil doc.head
    assert_nil doc.doctype
  end
  
  def test_doctype_parsing
    html = <<-EOF
<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body><p>Hello</p></body>
</html>
EOF
    
    doc = @create_doc.call(html.strip)
    assert_equal 'html', doc.doctype
  end
  
  def test_doctype_with_public_id
    html = '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">'
    
    doc = @create_doc.call(html)
    assert doc.doctype.include?('PUBLIC')
    assert doc.doctype.include?('W3C')
  end
  
  def test_head_parsing
    html = <<-EOF
<html>
<head>
  <title>Test Document</title>
  <meta charset="utf-8">
  <meta name="description" content="A test document">
  <link rel="stylesheet" href="style.css">
  <script src="script.js"></script>
  <style>body { margin: 0; }</style>
</head>
<body></body>
</html>
EOF
    
    doc = @create_doc.call(html.strip)
    
    head = doc.head
    assert_not_nil head
    assert_equal 'Test Document', head[:title]
    assert_equal 2, head[:meta].length
    assert_equal 1, head[:links].length
    assert_equal 1, head[:scripts].length
    assert_equal 1, head[:styles].length
    
    # Check meta attributes
    charset_meta = head[:meta].find do |meta|
      meta[:attributes].any? { |attr| attr[:name][:name] == 'charset' }
    end
    assert_not_nil charset_meta
    
    # Check link attributes
    link = head[:links][0]
    rel_attr = link[:attributes].find { |attr| attr[:name][:name] == 'rel' }
    assert_equal 'stylesheet', rel_attr[:value]
    
    # Check style content
    assert head[:styles][0][:content].include?('margin: 0')
  end
  
  def test_simple_paragraph
    html = '<p>Hello world</p>'
    
    doc = @create_doc.call(html)
    
    assert_equal 1, doc.body.length
    
    paragraph = doc.body[0]
    assert_equal 'paragraph', paragraph[:type]
    assert_equal 1, paragraph[:content].length
    assert_equal 'text', paragraph[:content][0][:type]
    assert_equal 'Hello world', paragraph[:content][0][:content]
  end
  
  def test_headings
    html = <<-EOF
<h1>Heading 1</h1>
<h2>Heading 2</h2>
<h3>Heading 3</h3>
<h4>Heading 4</h4>
<h5>Heading 5</h5>
<h6>Heading 6</h6>
EOF
    
    doc = @create_doc.call(html.strip)
    
    assert_equal 6, doc.body.length
    
    (1..6).each do |i|
      heading = doc.body[i-1]
      assert_equal 'heading', heading[:type]
      assert_equal i, heading[:level]
      assert_equal "Heading #{i}", heading[:content][0][:content]
    end
  end
  
  def test_semantic_elements
    html = <<-EOF
<main>
  <article>
    <header><h1>Article Title</h1></header>
    <section><p>Content here</p></section>
    <aside><p>Side note</p></aside>
    <footer><p>Article footer</p></footer>
  </article>
</main>
<nav><p>Navigation</p></nav>
EOF
    
    doc = @create_doc.call(html.strip)
    
    assert_equal 2, doc.body.length
    
    main_element = doc.body[0]
    assert_equal 'main', main_element[:type]
    
    article = main_element[:blocks][0]
    assert_equal 'article', article[:type]
    assert_equal 4, article[:blocks].length
    
    # Check nested semantic elements
    header = article[:blocks][0]
    assert_equal 'header', header[:type]
    
    section = article[:blocks][1]
    assert_equal 'section', section[:type]
    
    aside = article[:blocks][2]
    assert_equal 'aside', aside[:type]
    
    footer = article[:blocks][3]
    assert_equal 'footer', footer[:type]
    
    nav = doc.body[1]
    assert_equal 'nav', nav[:type]
  end
  
  def test_lists
    html = <<-EOF
<ul>
  <li>First item</li>
  <li>Second item</li>
</ul>
<ol>
  <li>Ordered item 1</li>
  <li>Ordered item 2</li>
</ol>
EOF
    
    doc = @create_doc.call(html.strip)
    
    assert_equal 2, doc.body.length
    
    ul = doc.body[0]
    assert_equal 'list', ul[:type]
    assert_equal 'unordered', ul[:list_type]
    assert_equal 2, ul[:items].length
    
    ol = doc.body[1]
    assert_equal 'list', ol[:type]
    assert_equal 'ordered', ol[:list_type]
    assert_equal 2, ol[:items].length
    
    # Check list item content
    first_item = ul[:items][0]
    assert_equal 1, first_item[:blocks].length
    # The li content should be parsed as blocks, likely a paragraph
  end
  
  def test_table
    html = <<-EOF
<table>
  <thead>
    <tr>
      <th>Header 1</th>
      <th>Header 2</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Cell 1</td>
      <td>Cell 2</td>
    </tr>
  </tbody>
</table>
EOF
    
    doc = @create_doc.call(html.strip)
    
    assert_equal 1, doc.body.length
    
    table = doc.body[0]
    assert_equal 'table', table[:type]
    
    assert_not_nil table[:head]
    assert_equal 1, table[:head][:rows].length
    
    header_row = table[:head][:rows][0]
    assert_equal 2, header_row[:cells].length
    assert_equal 'header', header_row[:cells][0][:cell_type]
    assert_equal 'header', header_row[:cells][1][:cell_type]
    
    assert_not_nil table[:body]
    assert_equal 1, table[:body][:rows].length
    
    data_row = table[:body][:rows][0]
    assert_equal 2, data_row[:cells].length
    assert_equal 'data', data_row[:cells][0][:cell_type]
    assert_equal 'data', data_row[:cells][1][:cell_type]
  end
  
  def test_blockquote
    html = '<blockquote><p>This is a quote</p></blockquote>'
    
    doc = @create_doc.call(html)
    
    assert_equal 1, doc.body.length
    
    blockquote = doc.body[0]
    assert_equal 'blockquote', blockquote[:type]
    assert_equal 1, blockquote[:blocks].length
    assert_equal 'paragraph', blockquote[:blocks][0][:type]
  end
  
  def test_blockquote_with_cite
    html = '<blockquote cite="http://example.com"><p>Quote with citation</p></blockquote>'
    
    doc = @create_doc.call(html)
    
    blockquote = doc.body[0]
    assert_equal 'blockquote', blockquote[:type]
    assert_equal 'http://example.com', blockquote[:cite]
  end
  
  def test_preformatted_text
    html = '<pre>  Preformatted\n  text here</pre>'
    
    doc = @create_doc.call(html)
    
    assert_equal 1, doc.body.length
    
    pre = doc.body[0]
    assert_equal 'pre', pre[:type]
    assert pre[:content][0][:content].include?('Preformatted')
  end
  
  def test_inline_elements
    html = '<p>This has <strong>bold</strong> and <em>italic</em> and <code>code</code> text.</p>'
    
    doc = @create_doc.call(html)
    
    paragraph = doc.body[0]
    content = paragraph[:content]
    
    # Should have multiple inline elements
    assert content.length > 3
    
    # Find emphasis elements
    strong_elem = content.find { |elem| elem[:type] == 'emphasis' && elem[:emphasis_type] == 'strong' }
    assert_not_nil strong_elem
    
    em_elem = content.find { |elem| elem[:type] == 'emphasis' && elem[:emphasis_type] == 'em' }
    assert_not_nil em_elem
    
    code_elem = content.find { |elem| elem[:type] == 'code' }
    assert_not_nil code_elem
    assert_equal 'code', code_elem[:content]
  end
  
  def test_links
    html = '<p>Visit <a href="http://example.com" title="Example">Example.com</a> for more info.</p>'
    
    doc = @create_doc.call(html)
    
    paragraph = doc.body[0]
    link = paragraph[:content].find { |elem| elem[:type] == 'link' }
    
    assert_not_nil link
    assert_equal 'http://example.com', link[:href]
    assert_equal 'Example', link[:title]
    assert_equal 1, link[:content].length
    assert_equal 'Example.com', link[:content][0][:content]
  end
  
  def test_images
    html = '<p>Here is an image: <img src="image.jpg" alt="Description" title="Image Title"></p>'
    
    doc = @create_doc.call(html)
    
    paragraph = doc.body[0]
    image = paragraph[:content].find { |elem| elem[:type] == 'image' }
    
    assert_not_nil image
    assert_equal 'image.jpg', image[:src]
    assert_equal 'Description', image[:alt]
    assert_equal 'Image Title', image[:title]
  end
  
  def test_line_breaks
    html = '<p>Line one<br>Line two</p>'
    
    doc = @create_doc.call(html)
    
    paragraph = doc.body[0]
    line_break = paragraph[:content].find { |elem| elem[:type] == 'line_break' }
    
    assert_not_nil line_break
  end
  
  def test_attributes_parsing
    html = '<p class="test-class" id="test-id" data-value="custom" style="color: red;">Text</p>'
    
    doc = @create_doc.call(html)
    
    paragraph = doc.body[0]
    attributes = paragraph[:attributes]
    
    assert_equal 4, attributes.length
    
    class_attr = attributes.find { |attr| attr[:name][:type] == 'class' }
    assert_not_nil class_attr
    assert_equal 'test-class', class_attr[:value]
    
    id_attr = attributes.find { |attr| attr[:name][:type] == 'id' }
    assert_not_nil id_attr
    assert_equal 'test-id', id_attr[:value]
    
    data_attr = attributes.find { |attr| attr[:name][:type] == 'data_attr' }
    assert_not_nil data_attr
    assert_equal 'value', data_attr[:name][:name]
    assert_equal 'custom', data_attr[:value]
    
    style_attr = attributes.find { |attr| attr[:name][:type] == 'style' }
    assert_not_nil style_attr
    assert_equal 'color: red;', style_attr[:value]
  end
  
  def test_nested_elements
    html = <<-EOF
<div class="container">
  <section>
    <h2>Section Title</h2>
    <p>Paragraph in section</p>
  </section>
</div>
EOF
    
    doc = @create_doc.call(html.strip)
    
    assert_equal 1, doc.body.length
    
    div = doc.body[0]
    assert_equal 'div', div[:type]
    
    class_attr = div[:attributes].find { |attr| attr[:name][:type] == 'class' }
    assert_equal 'container', class_attr[:value]
    
    section = div[:blocks][0]
    assert_equal 'section', section[:type]
    assert_equal 2, section[:blocks].length
  end
  
  def test_comments_are_ignored
    html = '<!-- This is a comment --><p>Real content</p><!-- Another comment -->'
    
    doc = @create_doc.call(html)
    
    # Comments should be ignored in parsing
    assert_equal 1, doc.body.length
    assert_equal 'paragraph', doc.body[0][:type]
  end
  
  # ========================================
  # RENDER TESTS
  # ========================================
  
  def test_render_empty_document
    doc = @create_doc.call("")
    rendered = doc.render
    
    assert rendered.include?('<html>')
    assert rendered.include?('<body>')
    assert rendered.include?('</body>')
    assert rendered.include?('</html>')
  end
  
  def test_render_doctype
    html = '<!DOCTYPE html><html><body><p>Test</p></body></html>'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('<!DOCTYPE html>')
  end
  
  def test_render_head_with_title
    html = <<-EOF
<html>
<head>
  <title>Test Page</title>
  <meta charset="utf-8">
</head>
<body></body>
</html>
EOF
    
    doc = @create_doc.call(html.strip)
    rendered = doc.render
    
    assert rendered.include?('<title>Test Page</title>')
    assert rendered.include?('<meta charset="utf-8">')
  end
  
  def test_render_paragraph
    html = '<p>Hello world</p>'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('<p>Hello world</p>')
  end
  
  def test_render_headings
    html = '<h1>Main Title</h1><h2>Subtitle</h2>'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('<h1>Main Title</h1>')
    assert rendered.include?('<h2>Subtitle</h2>')
  end
  
  def test_render_semantic_elements
    html = '<main><article><p>Content</p></article></main>'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('<main>')
    assert rendered.include?('<article>')
    assert rendered.include?('</article>')
    assert rendered.include?('</main>')
  end
  
  def test_render_lists
    html = '<ul><li>Item 1</li><li>Item 2</li></ul>'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('<ul>')
    assert rendered.include?('<li>Item 1</li>')
    assert rendered.include?('<li>Item 2</li>')
    assert rendered.include?('</ul>')
  end
  
  def test_render_table
    html = <<-EOF
<table>
  <thead>
    <tr><th>Header</th></tr>
  </thead>
  <tbody>
    <tr><td>Data</td></tr>
  </tbody>
</table>
EOF
    
    doc = @create_doc.call(html.strip)
    rendered = doc.render
    
    assert rendered.include?('<table>')
    assert rendered.include?('<thead>')
    assert rendered.include?('<th>Header</th>')
    assert rendered.include?('<tbody>')
    assert rendered.include?('<td>Data</td>')
  end
  
  def test_render_emphasis
    html = '<p>This is <strong>bold</strong> and <em>italic</em>.</p>'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('<strong>bold</strong>')
    assert rendered.include?('<em>italic</em>')
  end
  
  def test_render_links
    html = '<p><a href="http://example.com" title="Example">Click here</a></p>'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('href="http://example.com"')
    assert rendered.include?('title="Example"')
    assert rendered.include?('>Click here</a>')
  end
  
  def test_render_images
    html = '<img src="image.jpg" alt="Description" title="Title">'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('<img')
    assert rendered.include?('src="image.jpg"')
    assert rendered.include?('alt="Description"')
    assert rendered.include?('title="Title"')
  end
  
  def test_render_attributes
    html = '<p class="test" id="para1" data-value="custom">Text</p>'
    
    doc = @create_doc.call(html)
    rendered = doc.render
    
    assert rendered.include?('class="test"')
    assert rendered.include?('id="para1"')
    assert rendered.include?('data-value="custom"')
  end
  
  def test_render_html_escaping
    html = '<p>&lt;script&gt;alert("test")&lt;/script&
