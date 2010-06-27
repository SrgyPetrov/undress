require File.expand_path(File.dirname(__FILE__) + "/../undress")

module Undress
  class Textile < Grammar
    whitelist_attributes :class, :id, :lang, :style, :colspan, :rowspan,
      :bgcolor, :align
    whitelist_styles :"background-color", :background, :"text-align", :"text-decoration",
      :"font-weight", :color
    DEFAULT_STYLES = {:"background-color" => /(#ffffff|white)/i,
      :background => /(#ffffff|white)/i,
      :"text-align" => /left/i,
      :"text-decoration" => /none/i,
      :color => /(#000000|black)/i }


    # we try to get rid of unnecessary paras...
    pre_processing("td p, th p, li p") do |p|
      # only work on single children...
      unless p.parent.children.detect{ |sib| sib != p and sib.to_html.match /\S/}
        Hpricot::Elements[p.parent].set p.attributes.to_hash
        p.swap p.inner_html
      end
    end

    # entities
    post_processing(/&nbsp;/, " ")

    # whitespace handling
    post_processing(/\n\n+/, "\n\n")
    post_processing(/\A\s+/, "")
    post_processing(/\s+\z/, "\n")

    # special characters introduced by textile
    post_processing(/&#8230;/, "...")
    post_processing(/&#8217;/, "'")
    post_processing(/&#822[01];/, '"')
    post_processing(/&#8212;/, "--")
    post_processing(/&#8211;/, "-")
    post_processing(/(\d+\s*)&#215;(\s*\d+)/, '\1x\2')
    post_processing(/&#174;/, "(r)")
    post_processing(/&#169;/, "(c)")
    post_processing(/&#8482;/, "(tm)")

    # inline elements
    rule_for(:a) {|e|
      title = e.has_attribute?("title") ? " (#{e["title"]})" : ""
      "[#{content_of(e)}#{title}:#{e["href"]}]"
    }
    rule_for(:img) {|e|
      alt = e.has_attribute?("alt") && e["alt"]
      alt = "(#{alt})" unless alt == ""
      "!#{e["src"]}#{alt}!"
    }
    rule_for(:span)  {|e| attributes(e) == "" ? content_of(e) : wrap_with('%', e) }
    rule_for(:div)  {|e| attributes(e) == "" ? "#{content_of(e)}\n\n" : "#{wrap_with('%', e)}\n\n" }
    rule_for(:strong, :b)  {|e| wrap_with('*', e) }
    rule_for(:em)      {|e| wrap_with('_', e) }
    rule_for(:code)    {|e| "@#{attributes(e)}#{content_of(e)}@" }
    rule_for(:cite)    {|e| "??#{attributes(e)}#{content_of(e)}??" }
    rule_for(:sup)     {|e| wrap_with('^', e, surrounded_by_whitespace?(e)) }
    rule_for(:sub)     {|e| wrap_with('~', e, surrounded_by_whitespace?(e)) }
    rule_for(:ins)     {|e| wrap_with('+', e) }
    rule_for(:del)     {|e| wrap_with('-', e) }
    rule_for(:acronym) {|e| e.has_attribute?("title") ? "#{content_of(e)}(#{e["title"]})" : content_of(e) }

    def wrap_with(char, node, wrap = nil)
      wrap = complete_node?(node) if wrap.nil?
      content = content_of(node)
      prefix = content.lstrip! ? " " : ""
      postfix = content.chomp! ? "<br/>" : ""
      postfix = content.rstrip! ? " #{postfix}" : postfix
      return if content == ""
      if wrap
        "#{prefix}#{char}#{attributes(node)}#{content}#{char}#{postfix}"
      else
        "#{prefix}[#{char}#{attributes(node)}#{content}#{char}]#{postfix}"
      end
    end

    # text formatting and layout
    rule_for(:p, :div) do |e|
      at = ( e.name == 'div' or attributes(e) != "" ) ?
        "#{e.name}#{attributes(e)}. " : ""
      if e.parent
        case e.parent.name
        when "blockquote" then "#{at}#{content_of(e)}\n\n"
        when "td" then "#{content_of(e)}<br/>"
        when "th" then "#{content_of(e)}<br/>"
        when "li" then "#{content_of(e)}<br/>"
        else "\n\n#{at}#{content_of(e)}\n\n"
        end
      else
        "\n\n#{at}#{content_of(e)}\n\n"
      end
    end

    rule_for(:br)         {|e| "\n" }
    rule_for(:blockquote) {|e| "\n\nbq#{attributes(e)}. #{content_of(e)}\n\n" }
    rule_for(:pre)        {|e|
      if e.children && e.children.all? {|n| n.text? && n.content =~ /^\s+$/ || n.elem? && n.name == "code" }
        "\n\npc#{attributes(e)}. #{content_of(e % "code")}\n\n"
      else
        "<pre>#{content_of(e)}</pre>"
      end
    }

    # headings
    rule_for(:h1) {|e| "\n\nh1#{attributes(e)}. #{content_of(e)}\n\n" }
    rule_for(:h2) {|e| "\n\nh2#{attributes(e)}. #{content_of(e)}\n\n" }
    rule_for(:h3) {|e| "\n\nh3#{attributes(e)}. #{content_of(e)}\n\n" }
    rule_for(:h4) {|e| "\n\nh4#{attributes(e)}. #{content_of(e)}\n\n" }
    rule_for(:h5) {|e| "\n\nh5#{attributes(e)}. #{content_of(e)}\n\n" }
    rule_for(:h6) {|e| "\n\nh6#{attributes(e)}. #{content_of(e)}\n\n" }

    # lists
    rule_for(:li) {|e|
      token = e.parent.name == "ul" ? "*" : "#"
      nesting = e.ancestors.inject(1) {|total,node| total + (%(ul ol).include?(node.name) ? 0 : 1) }
      "\n#{token * nesting}#{start} #{content_of(e)}"
    }
    rule_for(:ul, :ol) {|e|
      if e.ancestors.detect {|node| %(ul ol).include?(node.name) }
        content_of(e)
      elsif e.ancestor('td')
        "#{content_of(e)}\n\n"
      else
        "\n#{content_of(e)}\n\n"
      end
    }

    # definition lists
    rule_for(:dl) {|e| "\n\n#{content_of(e)}\n" }
    rule_for(:dt) {|e| "- #{content_of(e)} " }
    rule_for(:dd) {|e| ":= #{content_of(e)} =:\n" }

    # tables
    rule_for(:table)   {|e| complex_table?(e) ? html_node(e) :
      "#{table_attributes(e)}\n#{content_of(e)}" }
    rule_for(:tr)      {|e| complex_table?(e) ? html_node(e) :
      "#{row_attributes(e)}#{content_of(e)}|\n" }
    rule_for(:td, :th) {|e| complex_table?(e) ? html_node(e) :
      "|#{cell_attributes(e)}#{cell_content_of(e)}" }

    # if a table contains a list or a another table we need html table syntax
    def complex_table?(node)
      return false unless %(table tr td th).include?(node.name)
      table = node.ancestor 'table'
      table.search('table, li').any?
    end

    def html_node(node)
      "<#{node.name} #{attributes(node, false)}>\n#{content_of(node)}</#{node.name}>\n"
    end

    def attributes(node, textile=true) #:nodoc:
      filtered ||= super(node)
      attribs = ""

      if filtered
        if colspan = filtered.delete(:colspan)
          attribs += textile ? "\\#{colspan}" : "colspan = #{colspan} "
        end

        if rowspan = filtered.delete(:rowspan)
          attribs += textile ? "/#{rowspan}" : "rowspan = #{colspan} "
        end

        if lang = filtered.delete(:lang)
          attribs += textile ? "[#{lang}]" : "lang=#{lang} "
        end

        if klass = filtered.delete(:class)
          klass.sub!(/(odd|even) ?/, '') if node.name == 'tr'
          klass.sub!(/caps ?/, '') if node.name == 'span'
        end
        id = filtered.delete(:id)
        if (klass && klass != '') or id
          if textile
            id = id.nil? ? "" : "#" + id
            attribs << "(#{klass}#{id})"
          else
            attribs << "class=#{klass} "
            attribs << "id=#{id} "
          end
        end

        styles = styles(node) || {}
        if bgcolor = filtered.delete(:bgcolor)
          styles[%s:background-color:] ||= bgcolor
        end

        align = styles.delete(%s:text-align:) if textile
        align ||= filtered.delete(:align)
        if align and textile
          attribs += case align.downcase
                     when 'center' then '='
                     when 'right'  then '>'
                     when 'justify' then '<>'
                     end
        end

        css = process_css(node, styles)
        if css && css != ""
          attribs += textile ? "{#{css}}" : %Q(style="#{css}" )
        end

      end
      attribs
    end

    def process_css(node, styles)
      return unless node
      css = ''
      styles.each_pair do |key, value|
        next if DEFAULT_STYLES[key] === value
        case key
        when :background
          # no position
          value.gsub!(/\s*\d+%/,'')
          # no image
          value.gsub!(/\s*url\([\)]*\)/,'')
          # no repeat
          value.gsub!(/\s*(no-)?repeat(-[xy])?/,'')
          # no attachement
          value.gsub!(/\s*(fixed|scroll)/,'')
          # no none
          value.gsub!(/\s*none/,'')
          # only background color remains
          value.gsub!(/\s/,'')
          css << "#{key}: #{value}; " if value != ''
        else
          css << "#{key}: #{value}; " if value != ''
        end
      end
      # remove dangling ;
      css.sub!(/;\s*$/,'')
    end

    def table_attributes(node)
      attributes(node) == "" ? "" : "table#{attributes(node)}. "
    end

    def row_attributes(node)
      attributes(node) == "" ? "" : "#{attributes(node)}. "
    end

    def cell_attributes(node)
      ret = (node.name == 'th') ? "_#{attributes(node)}" : attributes(node)
      return if ret.nil? or ret == ''
      ret[-1] == '.' ? "#{ret} " : "#{ret}. "
    end

    # some textile does not work in table cells.
    # trying to work around this as good as possible
    def cell_content_of(node)
      content = content_of(node)
      return " " if content == ""
      # p in cells does not work. apply the style to td instead.
      # TODO: figure out if we have some style applied already.
      if content[0..1] == 'p{'
        content[1..-1]
      else
        content
      end
    end
  end


  add_markup :textile, Textile
end
