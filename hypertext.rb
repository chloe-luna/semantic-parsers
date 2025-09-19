class Hypertext
  attr_reader :head, :body, :doctype
  
  def initialize(html)
    @html = html
    @head = nil
    @body = []
    @doctype = nil
    @tokens = []
    @current_token = 0
  end
  
  def solve
    @tokens = tokenize(@html)
    @current_token = 0
    
    # Parse doctype
    parse_doctype
    
    # Find and parse html element
    html_element = find_html_element
    if html_element
      parse_html_content(html_element)
    else
      # Treat entire content as body if no html wrapper
      @body = parse_blocks(@tokens)
    end
    
    self
  end
  
  def render
    output = []
    
    # Render doctype
    if @doctype
      output << "<!DOCTYPE #{@doctype}>"
    end
    
    # Render html wrapper
    output << "<html>"
    
    # Render head
    if @head
      output << render_head(@head)
    end
    
    # Render body
    output << "<body>"
    @body.each do |block|
      rendered_block = render_block(block)
      output << rendered_block if rendered_block && !rendered_block.empty?
    end
    output << "</body>"
    
    output << "</html>"
    output.join("\n")
  end
  
  private
  
  def tokenize(html)
    tokens = []
    remaining = html.strip
    
    while !remaining.empty?
      # Comments
      if remaining =~ /^<!--(.*?)-->/m
        comment_content = $1
        remaining = remaining[comment_content.length + 7..-1] || ""
        tokens << { :type => 'comment', :content => comment_content }
      
      # Doctype
      elsif remaining =~ /^<!DOCTYPE\s+([^>]+)>/i
        doctype_content = $1.strip
        remaining = remaining[$&.length..-1] || ""
        tokens << { :type => 'doctype', :content => doctype_content }
      
      # Opening tags
      elsif remaining =~ /^<([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^>]*)?)\s*>/
        tag_name = $1.downcase
        attributes_str = $2
        full_match = $&
        remaining = remaining[full_match.length..-1] || ""
        
        attributes = parse_attributes(attributes_str)
        tokens << { :type => 'open_tag', :tag => tag_name, :attributes => attributes }
      
      # Self-closing tags
      elsif remaining =~ /^<([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^>]*)?)\/\s*>/
        tag_name = $1.downcase
        attributes_str = $2
        full_match = $&
        remaining = remaining[full_match.length..-1] || ""
        
        attributes = parse_attributes(attributes_str)
        tokens << { :type => 'self_closing', :tag => tag_name, :attributes => attributes }
      
      # Closing tags
      elsif remaining =~ /^<\/([a-zA-Z][a-zA-Z0-9]*)\s*>/
        tag_name = $1.downcase
        remaining = remaining[$&.length..-1] || ""
        tokens << { :type => 'close_tag', :tag => tag_name }
      
      # Text content
      else
        if remaining =~ /^([^<]+)/
          text_content = $1
          remaining = remaining[text_content.length..-1] || ""
          # Don't add empty or whitespace-only text nodes between block elements
          unless text_content.strip.empty?
            tokens << { :type => 'text', :content => text_content }
          end
        else
          # Single character fallback
          tokens << { :type => 'text', :content => remaining[0,1] }
          remaining = remaining[1..-1] || ""
        end
      end
    end
    
    tokens
  end
  
  def parse_attributes(attr_string)
    return [] if attr_string.nil? || attr_string.strip.empty?
    
    attributes = []
    remaining = attr_string.strip
    
    while !remaining.empty?
      # Attribute with quoted value: name="value"
      if remaining =~ /^([a-zA-Z][a-zA-Z0-9-]*)\s*=\s*"([^"]*)"/
        attr_name = $1
        attr_value = $2
        remaining = remaining[$&.length..-1].strip
        attributes << parse_attribute_name_value(attr_name, attr_value)
      
      # Attribute with single-quoted value: name='value'
      elsif remaining =~ /^([a-zA-Z][a-zA-Z0-9-]*)\s*=\s*'([^']*)'/
        attr_name = $1
        attr_value = $2
        remaining = remaining[$&.length..-1].strip
        attributes << parse_attribute_name_value(attr_name, attr_value)
      
      # Attribute with unquoted value: name=value
      elsif remaining =~ /^([a-zA-Z][a-zA-Z0-9-]*)\s*=\s*([^\s>]+)/
        attr_name = $1
        attr_value = $2
        remaining = remaining[$&.length..-1].strip
        attributes << parse_attribute_name_value(attr_name, attr_value)
      
      # Boolean attribute: just name
      elsif remaining =~ /^([a-zA-Z][a-zA-Z0-9-]*)/
        attr_name = $1
        remaining = remaining[$&.length..-1].strip
        attributes << parse_attribute_name_value(attr_name, "")
      
      else
        break
      end
    end
    
    attributes
  end
  
  def parse_attribute_name_value(name, value)
    attr_name = case name.downcase
      when 'class' then { :type => 'class' }
      when 'id' then { :type => 'id' }
      when 'style' then { :type => 'style' }
      when 'title' then { :type => 'title' }
      when 'lang' then { :type => 'lang' }
      when 'dir' then { :type => 'dir' }
      else
        if name.start_with?('data-')
          { :type => 'data_attr', :name => name[5..-1] }
        else
          { :type => 'custom_attr', :name => name }
        end
    end
    
    { :name => attr_name, :value => value }
  end
  
  def parse_doctype
    doctype_token = @tokens.find { |token| token[:type] == 'doctype' }
    if doctype_token
      @doctype = doctype_token[:content]
      @tokens.reject! { |token| token[:type] == 'doctype' }
    end
  end
  
  def find_html_element
    html_start = @tokens.find_index { |token| token[:type] == 'open_tag' && token[:tag] == 'html' }
    html_end = nil
    
    if html_start
      # Find matching closing html tag
      level = 0
      (html_start + 1...@tokens.length).each do |i|
        token = @tokens[i]
        if token[:type] == 'open_tag' && token[:tag] == 'html'
          level += 1
        elsif token[:type] == 'close_tag' && token[:tag] == 'html'
          if level == 0
            html_end = i
            break
          else
            level -= 1
          end
        end
      end
    end
    
    if html_start && html_end
      @tokens[html_start + 1...html_end]
    else
      nil
    end
  end
  
  def parse_html_content(html_tokens)
    # Find head section
    head_start = html_tokens.find_index { |token| token[:type] == 'open_tag' && token[:tag] == 'head' }
    head_end = nil
    
    if head_start
      level = 0
      (head_start + 1...html_tokens.length).each do |i|
        token = html_tokens[i]
        if token[:type] == 'open_tag' && token[:tag] == 'head'
          level += 1
        elsif token[:type] == 'close_tag' && token[:tag] == 'head'
          if level == 0
            head_end = i
            break
          else
            level -= 1
          end
        end
      end
      
      if head_end
        head_tokens = html_tokens[head_start + 1...head_end]
        @head = parse_head(head_tokens)
      end
    end
    
    # Find body section
    body_start = html_tokens.find_index { |token| token[:type] == 'open_tag' && token[:tag] == 'body' }
    body_end = nil
    
    if body_start
      level = 0
      (body_start + 1...html_tokens.length).each do |i|
        token = html_tokens[i]
        if token[:type] == 'open_tag' && token[:tag] == 'body'
          level += 1
        elsif token[:type] == 'close_tag' && token[:tag] == 'body'
          if level == 0
            body_end = i
            break
          else
            level -= 1
          end
        end
      end
      
      if body_end
        body_tokens = html_tokens[body_start + 1...body_end]
        @body = parse_blocks(body_tokens)
      end
    end
  end
  
  def parse_head(tokens)
    title = nil
    meta_elements = []
    link_elements = []
    script_elements = []
    style_elements = []
    
    i = 0
    while i < tokens.length
      token = tokens[i]
      
      case token[:type]
      when 'open_tag'
        case token[:tag]
        when 'title'
          # Find matching close tag and extract text
          title_end = find_matching_close_tag(tokens, i, 'title')
          if title_end
            title_tokens = tokens[i + 1...title_end]
            title_text = title_tokens.select { |t| t[:type] == 'text' }.map { |t| t[:content] }.join('')
            title = title_text.strip
            i = title_end
          end
        when 'meta'
          meta_elements << { :attributes => token[:attributes] }
        when 'link'
          link_elements << { :attributes => token[:attributes] }
        when 'script'
          script_end = find_matching_close_tag(tokens, i, 'script')
          script_content = nil
          if script_end
            script_tokens = tokens[i + 1...script_end]
            script_text = script_tokens.select { |t| t[:type] == 'text' }.map { |t| t[:content] }.join('')
            script_content = script_text.strip unless script_text.strip.empty?
            i = script_end
          end
          script_elements << { :attributes => token[:attributes], :content => script_content }
        when 'style'
          style_end = find_matching_close_tag(tokens, i, 'style')
          style_content = ""
          if style_end
            style_tokens = tokens[i + 1...style_end]
            style_content = style_tokens.select { |t| t[:type] == 'text' }.map { |t| t[:content] }.join('')
            i = style_end
          end
          style_elements << { :attributes => token[:attributes], :content => style_content }
        end
      when 'self_closing'
        case token[:tag]
        when 'meta'
          meta_elements << { :attributes => token[:attributes] }
        when 'link'
          link_elements << { :attributes => token[:attributes] }
        end
      end
      
      i += 1
    end
    
    {
      :title => title,
      :meta => meta_elements,
      :links => link_elements,
      :scripts => script_elements,
      :styles => style_elements
    }
  end
  
  def find_matching_close_tag(tokens, start_index, tag_name)
    level = 0
    (start_index + 1...tokens.length).each do |i|
      token = tokens[i]
      if token[:type] == 'open_tag' && token[:tag] == tag_name
        level += 1
      elsif token[:type] == 'close_tag' && token[:tag] == tag_name
        if level == 0
          return i
        else
          level -= 1
        end
      end
    end
    nil
  end
  
  def parse_blocks(tokens)
    blocks = []
    i = 0
    
    while i < tokens.length
      token = tokens[i]
      
      if token[:type] == 'open_tag'
        block_info = parse_block_element(tokens, i)
        if block_info
          blocks << block_info[:block]
          i = block_info[:end_index]
        else
          i += 1
        end
      elsif token[:type] == 'text'
        # Collect consecutive text tokens as paragraph content
        text_content = []
        while i < tokens.length && tokens[i][:type] == 'text'
          text_content << tokens[i][:content]
          i += 1
        end
        
        unless text_content.join('').strip.empty?
          blocks << {
            :type => 'paragraph',
            :attributes => [],
            :content => [{ :type => 'text', :content => text_content.join('').strip }]
          }
        end
        i -= 1 # Adjust because the loop will increment
      end
      
      i += 1
    end
    
    blocks
  end
  
  def parse_block_element(tokens, start_index)
    token = tokens[start_index]
    return nil unless token[:type] == 'open_tag'
    
    tag = token[:tag]
    attributes = token[:attributes]
    
    # Find matching closing tag
    end_index = find_matching_close_tag(tokens, start_index, tag)
    return nil unless end_index
    
    # Extract content between tags
    content_tokens = tokens[start_index + 1...end_index]
    
    case tag
    when 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'
      level = tag[1].to_i
      inline_content = parse_inline_content(content_tokens)
      # For now, headings don't have nested blocks (would need lookahead parsing)
      {
        :block => {
          :type => 'heading',
          :level => level,
          :content => inline_content,
          :nested_blocks => []
        },
        :end_index => end_index
      }
    
    when 'p'
      inline_content = parse_inline_content(content_tokens)
      {
        :block => {
          :type => 'paragraph',
          :attributes => attributes,
          :content => inline_content
        },
        :end_index => end_index
      }
    
    when 'div'
      nested_blocks = parse_blocks(content_tokens)
      {
        :block => {
          :type => 'div',
          :attributes => attributes,
          :blocks => nested_blocks
        },
        :end_index => end_index
      }
    
    when 'section'
      nested_blocks = parse_blocks(content_tokens)
      {
        :block => {
          :type => 'section',
          :attributes => attributes,
          :blocks => nested_blocks
        },
        :end_index => end_index
      }
    
    when 'article'
      nested_blocks = parse_blocks(content_tokens)
      {
        :block => {
          :type => 'article',
          :attributes => attributes,
          :blocks => nested_blocks
        },
        :end_index => end_index
      }
    
    when 'aside'
      nested_blocks = parse_blocks(content_tokens)
      {
        :block => {
          :type => 'aside',
          :attributes => attributes,
          :blocks => nested_blocks
        },
        :end_index => end_index
      }
    
    when 'nav'
      nested_blocks = parse_blocks(content_tokens)
      {
        :block => {
          :type => 'nav',
          :attributes => attributes,
          :blocks => nested_blocks
        },
        :end_index => end_index
      }
    
    when 'main'
      nested_blocks = parse_blocks(content_tokens)
      {
        :block => {
          :type => 'main',
          :attributes => attributes,
          :blocks => nested_blocks
        },
        :end_index => end_index
      }
    
    when 'header'
      nested_blocks = parse_blocks(content_tokens)
      {
        :block => {
          :type => 'header',
          :attributes => attributes,
          :blocks => nested_blocks
        },
        :end_index => end_index
      }
    
    when 'footer'
      nested_blocks = parse_blocks(content_tokens)
      {
        :block => {
          :type => 'footer',
          :attributes => attributes,
          :blocks => nested_blocks
        },
        :end_index => end_index
      }
    
    when 'ul'
      list_items = parse_list_items(content_tokens, 'li')
      {
        :block => {
          :type => 'list',
          :list_type => 'unordered',
          :attributes => attributes,
          :items => list_items
        },
        :end_index => end_index
      }
    
    when 'ol'
      list_items = parse_list_items(content_tokens, 'li')
      {
        :block => {
          :type => 'list',
          :list_type => 'ordered',
          :attributes => attributes,
          :items => list_items
        },
        :end_index => end_index
      }
    
    when 'blockquote'
      nested_blocks = parse_blocks(content_tokens)
      cite = extract_cite_attribute(attributes)
      {
        :block => {
          :type => 'blockquote',
          :attributes => attributes,
          :blocks => nested_blocks,
          :cite => cite
        },
        :end_index => end_index
      }
    
    when 'pre'
      inline_content = parse_inline_content(content_tokens)
      {
        :block => {
          :type => 'pre',
          :attributes => attributes,
          :content => inline_content
        },
        :end_index => end_index
      }
    
    when 'table'
      table_data = parse_table(content_tokens)
      {
        :block => {
          :type => 'table',
          :attributes => attributes,
          :head => table_data[:head],
          :body => table_data[:body],
          :foot => table_data[:foot]
        },
        :end_index => end_index
      }
    
    else
      # Generic block element
      if is_block_element(tag)
        nested_blocks = parse_blocks(content_tokens)
        {
          :block => {
            :type => tag,
            :attributes => attributes,
            :blocks => nested_blocks
          },
          :end_index => end_index
        }
      else
        nil
      end
    end
  end
  
  def parse_inline_content(tokens)
    inline_elements = []
    i = 0
    
    while i < tokens.length
      token = tokens[i]
      
      case token[:type]
      when 'text'
        inline_elements << { :type => 'text', :content => token[:content] }
      
      when 'open_tag'
        inline_info = parse_inline_element(tokens, i)
        if inline_info
          inline_elements << inline_info[:element]
          i = inline_info[:end_index]
        else
          i += 1
        end
      
      when 'self_closing'
        case token[:tag]
        when 'img'
          src = extract_attribute_value(token[:attributes], 'src') || ''
          alt = extract_attribute_value(token[:attributes], 'alt') || ''
          title = extract_attribute_value(token[:attributes], 'title')
          inline_elements << {
            :type => 'image',
            :attributes => token[:attributes],
            :src => src,
            :alt => alt,
            :title => title
          }
        when 'br'
          inline_elements << { :type => 'line_break' }
        when 'input'
          input_type = extract_attribute_value(token[:attributes], 'type') || 'text'
          inline_elements << {
            :type => 'input',
            :input_type => input_type,
            :attributes => token[:attributes]
          }
        end
      end
      
      i += 1
    end
    
    inline_elements
  end
  
  def parse_inline_element(tokens, start_index)
    token = tokens[start_index]
    return nil unless token[:type] == 'open_tag'
    
    tag = token[:tag]
    attributes = token[:attributes]
    
    return nil if is_block_element(tag)
    
    # Find matching closing tag
    end_index = find_matching_close_tag(tokens, start_index, tag)
    return nil unless end_index
    
    # Extract content between tags
    content_tokens = tokens[start_index + 1...end_index]
    
    case tag
    when 'a'
      href = extract_attribute_value(attributes, 'href') || ''
      title = extract_attribute_value(attributes, 'title')
      inline_content = parse_inline_content(content_tokens)
      {
        :element => {
          :type => 'link',
          :attributes => attributes,
          :href => href,
          :title => title,
          :content => inline_content
        },
        :end_index => end_index
      }
    
    when 'strong', 'b'
      inline_content = parse_inline_content(content_tokens)
      {
        :element => {
          :type => 'emphasis',
          :emphasis_type => 'strong',
          :attributes => attributes,
          :content => inline_content
        },
        :end_index => end_index
      }
    
    when 'em', 'i'
      inline_content = parse_inline_content(content_tokens)
      {
        :element => {
          :type => 'emphasis',
          :emphasis_type => 'em',
          :attributes => attributes,
          :content => inline_content
        },
        :end_index => end_index
      }
    
    when 'code'
      text_content = content_tokens.select { |t| t[:type] == 'text' }.map { |t| t[:content] }.join('')
      {
        :element => {
          :type => 'code',
          :attributes => attributes,
          :content => text_content
        },
        :end_index => end_index
      }
    
    when 'span'
      inline_content = parse_inline_content(content_tokens)
      {
        :element => {
          :type => 'span',
          :attributes => attributes,
          :content => inline_content
        },
        :end_index => end_index
      }
    
    else
      # Generic inline element
      inline_content = parse_inline_content(content_tokens)
      {
        :element => {
          :type => tag,
          :attributes => attributes,
          :content => inline_content
        },
        :end_index => end_index
      }
    end
  end
  
  def parse_list_items(tokens, item_tag)
    items = []
    i = 0
    
    while i < tokens.length
      token = tokens[i]
      
      if token[:type] == 'open_tag' && token[:tag] == item_tag
        end_index = find_matching_close_tag(tokens, i, item_tag)
        if end_index
          item_tokens = tokens[i + 1...end_index]
          item_blocks = parse_blocks(item_tokens)
          items << {
            :attributes => token[:attributes],
            :blocks => item_blocks
          }
          i = end_index
        end
      end
      
      i += 1
    end
    
    items
  end
  
  def parse_table(tokens)
    head = nil
    body = nil
    foot = nil
    
    i = 0
    while i < tokens.length
      token = tokens[i]
      
      if token[:type] == 'open_tag'
        case token[:tag]
        when 'thead'
          end_index = find_matching_close_tag(tokens, i, 'thead')
          if end_index
            head_tokens = tokens[i + 1...end_index]
            head = parse_table_section(head_tokens)
            i = end_index
          end
        when 'tbody'
          end_index = find_matching_close_tag(tokens, i, 'tbody')
          if end_index
            body_tokens = tokens[i + 1...end_index]
            body = parse_table_section(body_tokens)
            i = end_index
          end
        when 'tfoot'
          end_index = find_matching_close_tag(tokens, i, 'tfoot')
          if end_index
            foot_tokens = tokens[i + 1...end_index]
            foot = parse_table_section(foot_tokens)
            i = end_index
          end
        when 'tr'
          # Direct tr without section wrapper
          if head.nil?
            head = parse_table_section(tokens[i..-1])
          end
        end
      end
      
      i += 1
    end
    
    { :head => head, :body => body, :foot => foot }
  end
  
  def parse_table_section(tokens)
    rows = []
    i = 0
    
    while i < tokens.length
      token = tokens[i]
      
      if token[:type] == 'open_tag' && token[:tag] == 'tr'
        end_index = find_matching_close_tag(tokens, i, 'tr')
        if end_index
          row_tokens = tokens[i + 1...end_index]
          row = parse_table_row(row_tokens)
          rows << row
          i = end_index
        end
      end
      
      i += 1
    end
    
    { :rows => rows }
  end
  
  def parse_table_row(tokens)
    cells = []
    i = 0
    
    while i < tokens.length
      token = tokens[i]
      
      if token[:type] == 'open_tag' && (token[:tag] == 'td' || token[:tag] == 'th')
        end_index = find_matching_close_tag(tokens, i, token[:tag])
        if end_index
          cell_tokens = tokens[i + 1...end_index]
          cell_blocks = parse_blocks(cell_tokens)
          cell_type = token[:tag] == 'th' ? 'header' : 'data'
          cells << {
            :cell_type => cell_type,
            :attributes => token[:attributes],
            :blocks => cell_blocks
          }
          i = end_index
        end
      end
      
      i += 1
    end
    
    { :attributes => [], :cells => cells }
  end
  
  def is_block_element(tag)
    %w[
      div p h1 h2 h3 h4 h5 h6 section article aside nav main header footer
      ul ol li blockquote pre table thead tbody tfoot tr td th
      figure figcaption details summary address form fieldset
    ].include?(tag)
  end
  
  def extract_attribute_value(attributes, attr_name)
    attr = attributes.find do |a| 
      a[:name][:type] == attr_name || 
      (a[:name][:type] == 'custom_attr' && a[:name][:name] == attr_name)
    end
    attr ? attr[:value] : nil
  end
  
  def extract_cite_attribute(attributes)
    extract_attribute_value(attributes, 'cite')
  end
  
  # ========================================
  # RENDERING METHODS
  # ========================================
  
  def render_head(head)
    output = ["<head>"]
    
    # Render title
    if head[:title]
      output << "  <title>#{escape_html(head[:title])}</title>"
    end
    
    # Render meta elements
    head[:meta].each do |meta|
      output << "  #{render_self_closing_tag('meta', meta[:attributes])}"
    end
    
    # Render link elements
    head[:links].each do |link|
      output << "  #{render_self_closing_tag('link', link[:attributes])}"
    end
    
    # Render style elements
    head[:styles].each do |style|
      attrs_str = render_attributes(style[:attributes])
      output << "  <style#{attrs_str}>#{style[:content]}</style>"
    end
    
    # Render script elements
    head[:scripts].each do |script|
      attrs_str = render_attributes(script[:attributes])
      if script[:content]
        output << "  <script#{attrs_str}>#{script[:content]}</script>"
      else
        output << "  <script#{attrs_str}></script>"
      end
    end
    
    output << "</head>"
    output.join("\n")
  end
  
  def render_block(block)
    case block[:type]
    when 'heading'
      render_heading(block)
    when 'paragraph'
      render_paragraph(block)
    when 'div'
      render_container_block('div', block)
    when 'section'
      render_container_block('section', block)
    when 'article'
      render_container_block('article', block)
    when 'aside'
      render_container_block('aside', block)
    when 'nav'
      render_container_block('nav', block)
    when 'main'
      render_container_block('main', block)
    when 'header'
      render_container_block('header', block)
    when 'footer'
      render_container_block('footer', block)
    when 'list'
      render_list(block)
    when 'blockquote'
      render_blockquote(block)
    when 'pre'
      render_pre(block)
    when 'table'
      render_table(block)
    else
      ""
    end
  end
  
  def render_heading(block)
    level = block[:
