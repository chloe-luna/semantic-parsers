# Example usage:
# doc = MarkdownDocument.new(markdown_text)
# doc.solve
# puts doc.blocks.inspect

class MarkdownDocument
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
  
  def render
    output = []
    
    # Render frontmatter
    if @metadata
      delimiter = @metadata[:type] == 'YAML' ? '---' : '+++'
      output << delimiter
      output << @metadata[:content]
      output << delimiter
      output << ''  # blank line after frontmatter
    end
    
    # Render blocks
    @blocks.each_with_index do |block, index|
      rendered_block = render_block(block)
      output << rendered_block if rendered_block && !rendered_block.empty?
      
      # Add spacing between blocks (except after last block)
      if index < @blocks.length - 1 && !rendered_block.empty?
        next_block = @blocks[index + 1]
        # Don't add extra space before horizontal rules or after headings with nested content
        unless next_block[:type] == 'horizontal_rule' || 
               (block[:type] == 'heading' && block[:nested_blocks] && !block[:nested_blocks].empty?)
          output << ''
        end
      end
    end
    
    # Render footnotes
    unless @footnotes.empty?
      output << '' unless output.empty?
      @footnotes.each do |ref, content|
        output << "[^#{ref}]: #{content}"
      end
    end
    
    # Render references
    unless @references.empty?
      output << '' unless output.empty? && @footnotes.empty?
      @references.each do |ref, data|
        title_part = data[:title] ? " \"#{data[:title]}\"" : ""
        output << "[#{ref}]: #{data[:url]}#{title_part}"
      end
    end
    
    output.join("\n")
  end
  
  private
  
  def render_block(block)
    case block[:type]
    when 'heading'
      render_heading(block)
    when 'paragraph'
      render_paragraph(block)
    when 'code_block'
      render_code_block(block)
    when 'blockquote'
      render_blockquote(block)
    when 'list'
      render_list(block)
    when 'horizontal_rule'
      render_horizontal_rule(block)
    when 'table'
      render_table(block)
    else
      ""
    end
  end
  
  def render_heading(block)
    level = block[:level] || 1
    prefix = '#' * level
    content = render_inline_content(block[:content] || [])
    result = "#{prefix} #{content}"
    
    # Render nested blocks if present
    if block[:nested_blocks] && !block[:nested_blocks].empty?
      result += "\n\n"
      nested_content = block[:nested_blocks].map { |nested_block| render_block(nested_block) }.join("\n\n")
      result += nested_content
    end
    
    result
  end
  
  def render_paragraph(block)
    render_inline_content(block[:content] || [])
  end
  
  def render_code_block(block)
    if block[:subtype] == 'fenced'
      fence = '```'
      language = block[:language] ? block[:language] : ''
      "#{fence}#{language}\n#{block[:content] || ''}\n#{fence}"
    else # indented
      lines = (block[:content] || '').split("\n")
      lines.map { |line| "    #{line}" }.join("\n")
    end
  end
  
  def render_blockquote(block)
    nested_blocks = block[:blocks] || []
    if nested_blocks.empty?
      "> "
    else
      nested_content = nested_blocks.map { |nested_block| render_block(nested_block) }.join("\n\n")
      lines = nested_content.split("\n")
      lines.map { |line| "> #{line}" }.join("\n")
    end
  end
  
  def render_list(block)
    items = block[:items] || []
    list_type = block[:list_type] || {}
    result_lines = []
    
    items.each_with_index do |item, index|
      # Generate marker
      if list_type[:type] == 'ordered'
        start_num = list_type[:start] || 1
        marker = "#{start_num + index}."
      else
        bullet_char = case list_type[:bullet]
          when 'dash' then '-'
          when 'plus' then '+'
          else '*'  # asterisk or default
        end
        marker = bullet_char
      end
      
      # Add task status if present
      task_prefix = ""
      if item[:task_status]
        checkbox = item[:task_status] == 'completed' ? '[x]' : '[ ]'
        task_prefix = "#{checkbox} "
      end
      
      # Render item content
      content = render_inline_content(item[:content] || [])
      result_lines << "#{marker} #{task_prefix}#{content}"
      
      # Render nested blocks if present
      if item[:nested_blocks] && !item[:nested_blocks].empty?
        nested_content = item[:nested_blocks].map { |nested_block| render_block(nested_block) }
        nested_content.each do |nested_line|
          # Indent nested content
          nested_line.split("\n").each do |line|
            result_lines << "  #{line}"
          end
        end
      end
    end
    
    result_lines.join("\n")
  end
  
  def render_horizontal_rule(block)
    "---"
  end
  
  def render_table(block)
    result_lines = []
    
    # Render header
    if block[:header]
      header_cells = block[:header][:cells] || []
      header_content = header_cells.map { |cell| render_inline_content(cell[:content] || []) }
      result_lines << "| #{header_content.join(' | ')} |"
      
      # Render alignment row
      alignment_row = header_cells.map do |cell|
        case cell[:alignment]
        when 'left' then ':---'
        when 'center' then ':---:'
        when 'right' then '---:'
        else '---'  # default
        end
      end
      result_lines << "| #{alignment_row.join(' | ')} |"
    end
    
    # Render data rows
    rows = block[:rows] || []
    rows.each do |row|
      row_cells = row[:cells] || []
      row_content = row_cells.map { |cell| render_inline_content(cell[:content] || []) }
      result_lines << "| #{row_content.join(' | ')} |"
    end
    
    result_lines.join("\n")
  end
  
  def render_inline_content(inline_elements)
    return "" if inline_elements.nil? || inline_elements.empty?
    
    inline_elements.map { |element| render_inline_element(element) }.join("")
  end
  
  def render_inline_element(element)
    case element[:type]
    when 'text'
      element[:content] || ""
    when 'emphasis'
      render_emphasis(element)
    when 'code'
      "`#{element[:content] || ""}`"
    when 'link'
      render_link(element)
    when 'image'
      render_image(element)
    when 'line_break'
      "  \n"
    when 'soft_break'
      "\n"
    else
      ""
    end
  end
  
  def render_emphasis(element)
    content = render_inline_content(element[:content] || [])
    case element[:emphasis_type]
    when 'strong'
      "**#{content}**"
    when 'italic'
      "*#{content}*"
    when 'strikethrough'
      "~~#{content}~~"
    when 'underline'
      "<u>#{content}</u>"  # HTML fallback
    else
      content
    end
  end
  
  def render_link(element)
    content = render_inline_content(element[:content] || [])
    target = element[:target] || {}
    title = element[:title]
    
    if target[:type] == 'reference'
      ref = target[:ref] || content.downcase
      "[#{content}][#{ref}]"
    else
      url = target[:url] || ""
      title_part = title ? " \"#{title}\"" : ""
      "[#{content}](#{url}#{title_part})"
    end
  end
  
  def render_image(element)
    alt_text = render_inline_content(element[:content] || [])
    target = element[:target] || {}
    title = element[:title]
    
    if target[:type] == 'reference'
      ref = target[:ref] || alt_text.downcase
      "![#{alt_text}][#{ref}]"
    else
      url = target[:url] || ""
      title_part = title ? " \"#{title}\"" : ""
      "![#{alt_text}](#{url}#{title_part})"
    end
  end
  
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
      nested_parser = MarkdownDocument.new(quoted_text)
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
