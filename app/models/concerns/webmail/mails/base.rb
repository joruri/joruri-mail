module Webmail::Mails::Base
  @@search_contents_depth = 5

  def html_mail?
    #TODO: @mail.html_partで判定してはいけない？
    search_html = Proc.new do |p, lv|
      return true if !p.attachment? && p.mime_type == "text/html" 
      p.parts.each { |c| search_html.call(c, lv + 1) } if p.multipart? && lv < @@search_contents_depth
    end
    search_html.call(@mail, 0)
    false
  end

  def date(format = '%Y-%m-%d %H:%M', nullif = nil)
    @mail.date.blank? ? nullif : @mail.date.in_time_zone.strftime(format)
  rescue => e
    write_log(e)
    fallback_date_field(@mail.header[:date], format)
  end

  def from_addr
    extract_address_from_mail_list(friendly_from_addr)
  end

  def from_address
    Email.parse(friendly_from_addr)
  end

  def friendly_from_addr
    collect_addrs(@mail.header[:from]).first || 'unknown'
  rescue => e
    write_log(e)
    fallback_text_field(@mail.header[:from])
  end

  def friendly_to_addrs
    collect_addrs(@mail.header[:to])
  rescue => e
    write_log(e)
    [fallback_text_field(@mail.header[:to])]
  end

  def simple_to_addr
    addrs = friendly_to_addrs
    "#{addrs.first}#{%Q( 他) if addrs.size > 1}"
  end

  def friendly_cc_addrs
    collect_addrs(@mail.header[:cc])
  rescue => e
    write_log(e)
    [fallback_text_field(@mail.header[:cc])]
  end

  def friendly_bcc_addrs
    collect_addrs(@mail.header[:bcc])
  rescue => e
    write_log(e)
    [fallback_text_field(@mail.header[:bcc])]
  end

  def friendly_reply_to_addrs
    collect_addrs(@mail.header[:reply_to])
  rescue => e
    write_log(e)
    [fallback_text_field(@mail.header[:reply_to])]
  end

  def friendly_reply_to_addrs_for_answer(all_members = nil)
    addrs = collect_addrs(@mail.header[:reply_to])
    addrs = [friendly_from_addr] if addrs.blank?
    if all_members
      addrs += friendly_to_addrs
      addrs = uniq_addrs(addrs)
      addrs.delete_if{|a| a.index(Core.current_user.email)} if addrs.size > 1
    end
    addrs
  rescue => e
    write_log(e)
    [fallback_text_field(@mail.header[:reply_to])]
  end

  def sender
    field = @mail.header[:sender]
    field ? field.decoded : friendly_from_addr 
  rescue => e
    write_log(e)
    fallback_text_field(@mail.header[:sender])
  end

  def subject
    field = @mail.header[:subject]
    return 'no subject' unless field

    decoded = decode(field.decoded.to_s, auto_detect: field.value !~ Mail::Constants::ENCODED_VALUE)
    if (lang = subject_language).present?
      "【#{lang}】#{decoded}"
    else
      decoded
    end
  rescue => e
    write_log(e)
    fallback_text_field(@mail.header[:subject])
  end

  def subject_language
    field = @mail.header[:subject]
    encoding = ((mt = field.value.match(/=\?(.+?)\?[QB]\?(.+?)\?=/)) ? mt[1].downcase : '')
    if encoding.blank? || valid_encoding?(encoding)
      ''
    else
      lang = I18n.t(encoding, scope: :language)
      lang !~ /^translation missing/ ? "#{lang}/#{encoding}" : "#{encoding}"
    end
  end

  def priority
    @mail.header[:x_priority].to_s.scan(/^(\d)+/).flatten.first if @mail.header[:x_priority]
  end

  def has_disposition_notification_to?
    @mail.header[:disposition_notification_to].present?
  end

  def disposition_notification_to_addrs
    dnt = @mail.header[:disposition_notification_to]
    dnt.try(:field).try(:addrs) || []
  rescue => e
    write_log(e)
    []
  end

  def text_body
    return @text_body if @text_body

    inlines = inline_contents
    inlines.each do |content|
      if !content.attachment? && (content.alternative? || content.content_type == "text/plain" || content.content_type == "text/html") 
        @text_body = content.text_body
        break
      end
    end
    return @text_body
  end

  def html_image_was_omitted?
    @html_image_was_omitted
  end

  def html_body(options = {})
    return @html_body if @html_body

    inlines = inline_contents(options)
    inlines.each do |content|
      if !content.attachment? && (content.alternative? || content.content_type == "text/html")
        @html_body = content.html_body
        break
      end
    end
    @html_body
  end 

  def html_body_for_edit
    decoded = html_body(replace_cid: true)
    if decoded =~ /<body(\s+[^>]*)?>(.*)<\/body>/i
      $1
    else
      decoded
    end
  end

  def referenced_body(type = :answer)
    case type
    when :answer
      text_body.to_s.gsub(/\r\n/, "\n").gsub(/^/, "> ")
    when :forward
      referenced_body_for_forward(:text)
    end
  end

  def referenced_html_body(type = :answer)
    case type
    when :answer
      %Q(<blockquote>#{html_body_for_edit.to_s.gsub(/\r\n/, "\n")}</blockquote>\n)
    when :forward
      referenced_body_for_forward(:html)
    end
  end

  def has_attachments?
    pattern = /^multipart\/(mixed|related|report)$/
    search_multipart = Proc.new do |p, lv|
      return true if p.mime_type =~ pattern || p.attachment?
      p.parts.each {|c| search_multipart.call(c, lv + 1)} if p.multipart? && lv < @@search_contents_depth - 1
    end
    search_multipart.call(@mail, 0)
    false
  end

  def has_images?
    pattern = /^image\/(gif|jpeg|png|bmp)$/i
    search_multipart = Proc.new do |p, lv|
      return true if p.mime_type =~ pattern
      p.parts.each {|c| search_multipart.call(c, lv + 1)} if p.multipart? && lv < @@search_contents_depth - 1
    end
    search_multipart.call(@mail, 0)
    false
  end

  def attachments
    return @attachments if @attachments

    @attachments = []

    attached_files = lambda do |part, level|
      if part.attachment? && part.filename.present?
        seqno = @attachments.size
        begin
          body = part.decoded
        rescue => e
          write_log(e)
          body = part.body.raw_source
        end
        @attachments << Sys::Lib::Mail::Attachment.new(
          seqno:             seqno,
          content_type:      part.mime_type || 'application/octet-stream',
          name:              part.filename.force_encoding('utf-8').strip,
          body:              body,
          size:              body.bytesize,
          transfer_encoding: part.content_transfer_encoding
        )
      elsif part.multipart?
        part.parts.each { |p| attached_files.call(p, level + 1) } if level < @@search_contents_depth
      elsif part.mime_type == 'message/rfc822'
        mail = Mail::Message.new(part.body)
        attached_files.call(mail, 0)
      end
    end

    attached_files.call(@mail, 0)

    @attachments
  end

  def disposition_notification_mail?
    return true if @mail.mime_type == "multipart/report" &&
      @mail.content_type_parameters &&
      @mail.content_type_parameters['report-type'] == 'disposition-notification'
    return false
  end

  #def inline_contents
  #  inlines = []
  #  search_inline = Proc.new do |p, lv|
  #    if p.inline? && p.mime_type =~ /^text\/.+$/
  #      inlines << decode(p.body.decoded) if p.mime_type != "text/plain" || p.attachment?
  #    end
  #    p.parts.each { |c| search_inline.call(c, lv + 1) } if p.multipart? && lv < @@search_contents_depth
  #  end    
  #  @mail.parts.each {|p| search_inline.call(p, 1) } if @mail.multipart? 
  #  inlines
  #end

  def inline_contents(options = {})
    return @inline_contents if @inline_contents

    inlines = []
    alternates = []

    collect_text = Proc.new do |parent|
      text = nil
      parent.parts.each do |p|
        if p.mime_type == "text/plain" && !p.attachment?
          text ||= ''
          text += "\n" if text.present? 
          text += decode_text_part(p)
        end
      end
      text
    end

    collect_html = Proc.new do |parent|
      html = nil
      parent.parts.each do |p|
        if p.mime_type == "text/html" && !p.attachment?
          html ||= '' 
          html += "<p>#{decode_html_part(p, options)}</p>"
        end
      end
      html
    end

    search_inline = Proc.new do |p, lv|
      if lv == 0 || (p.inline? rescue false) || p.content_disposition.blank?
        case
        when p.mime_type == "text/plain" 
          inlines << Sys::Lib::Mail::Inline.new(
            seqno: inlines.size,
            content_type: p.mime_type,
            text_body: decode_text_part(p),
            attachment: p.attachment?
          ) if lv == 0 || p.attachment?
        when p.mime_type == "text/html"
          inlines << Sys::Lib::Mail::Inline.new(
            seqno: inlines.size,
            content_type: p.mime_type,
            html_body: decode_html_part(p, options),
            attachment: p.attachment?
          ) if lv == 0 || p.attachment?
        when p.mime_type =~ /^text\/.+$/
          inlines << Sys::Lib::Mail::Inline.new(
            seqno: inlines.size,
            content_type: p.mime_type,
            text_body: decode_text_part(p),
            attachment: p.attachment?)
        when p.mime_type == 'message/rfc822'
          mail = Mail::Message.new(p.body)
          search_inline.call(mail, 0)
        else
          inlines << Sys::Lib::Mail::Inline.new(
            seqno: inlines.size,
            content_type: "text/plain",
            text_body: decode_text_part(p)
          ) if lv == 0 && !p.multipart? && !p.attachment?
        end        
      end
      if p.multipart? && lv < @@search_contents_depth
        text = collect_text.call(p)
        html = collect_html.call(p)
        alt = nil
        if p.mime_type == "multipart/alternative"
          alt = Sys::Lib::Mail::Inline.new(seqno: inlines.size, alternative: true)
          alt.text_body = text if text.present?
          alt.html_body = html if html.present?
          inlines << alt
          alternates << alt
        else
          if text.present?
            if alternates[-1] && alternates[-1].text_body.blank?
              alternates[-1].text_body = text
            else
              inlines << Sys::Lib::Mail::Inline.new(
                seqno: inlines.size,
                content_type: "text/plain",
                text_body: text
              )
            end
          end
          if html.present?
            if alternates[-1] && alternates[-1].html_body.blank?
              alternates[-1].html_body = html
            else
              inlines << Sys::Lib::Mail::Inline.new(
                seqno: inlines.size,
                content_type: "text/html",
                html_body: html
              )
            end
          end
        end
        p.parts.each { |c| search_inline.call(c, lv + 1) }
        alternates.pop if p.mime_type == "multipart/alternative"
      end
    end

    search_inline.call(@mail, 0)

    inlines.each do |inline|
      if !inline.text_body && inline.html_body
        inline.text_body = convert_html_to_text(inline.html_body)
      end
    end

    @inline_contents = inlines
  end
  
  private

  def collect_addrs(field)
    return [] unless field

    addresses =
      if field.errors.blank?
        field.address_list.addresses
      else
        Email.parse_list(NKF.nkf('-w', field.value))
      end
    addresses.map do |addr|
      addr.name ? "#{Email.quote_phrase(addr.name)} <#{addr.address}>" : addr.address
    end
  end

  def uniq_addrs(addrs)
    new_addrs = {}
    addrs.each do |c|
      addr = c.gsub(/.*<(.*)>.*/, '\\1')
      new_addrs[addr] = c unless new_addrs.key?(addr)
    end
    new_addrs.values
  end

  def referenced_body_for_forward(format = :text)
    om = "----------------------- Original Message -----------------------\n"
    om << " From:    #{friendly_from_addr}\n"
    om << " To:      #{friendly_to_addrs.join(', ')}\n"
    om << " Cc:      #{friendly_cc_addrs.join(', ')}\n" if friendly_cc_addrs.size > 0
    om << " Date:    #{date('%Y-%m-%d %H:%M:%S')}\n"
    om << " Subject: #{subject}\n"
    om << "----\n\n"
    ome= "\n--------------------- Original Message Ends --------------------"

    if format == :html
      om = Util::String.text_to_html(om)
      ome = Util::String.text_to_html(ome)
      html = html_body_for_edit.to_s.gsub(/\r\n/, "\n")
      "#{om}#{html}#{ome}"
    else
      "#{om}#{text_body.to_s.gsub(/\r\n/, "\n")}#{ome}"
    end
  end

  def decode(str, auto_detect: false)
    str = str.to_s

    if auto_detect && (detection = CharlockHolmes::EncodingDetector.detect(str))
      charset = detection[:encoding].to_s
      if charset.downcase =~ Regexp.union(/^iso-2022-jp/, /^shift[_-]jis$/, /^euc-jp$/)
        str = NKF::nkf('-wx --cp932', str).gsub(/\0/, "")
      elsif (encoding = Encoding.find(charset) rescue nil) && encoding != Encoding::UTF_8
        str = str.dup.force_encoding(encoding).encode('utf-8', undef: :replace, invalid: :replace)
      end
    end

    str.dup.force_encoding('utf-8').encode('utf-8', undef: :replace, invalid: :replace)
  end

  def decode_text_part(part)
    decode(part.decoded.to_s, auto_detect: !part.has_charset?)
  rescue => e
    write_log(e)
    fallback_body_part(part)
  end

  def decode_html_part(part, options = {})
    body = decode_text_part(part)
    body, image_was_omitted = secure_html_body(body, options)
    @html_image_was_omitted = image_was_omitted

    unless options[:replace_cid] == false
      files = []

      search_inline_content = Proc.new do |p, lv|
        if p.mime_type == "multipart/related"
          p.parts.each {|f| files << f if f.header['content-id'] && f.filename }
        elsif p.multipart? && lv < @@search_contents_depth - 1
          p.parts.each { |c| search_inline_content.call(c, lv + 1) }  
        end
      end
      search_inline_content.call(@mail, 0)

      files.each_with_index do |f, idx|
        cid  = f.header['content-id'].value.gsub(/^<(.*)>$/, '\\1')

        if options[:embed_image] && (data = Base64.encode64(f.decoded)) && data.size < options[:embed_image_size_limit]
          body = body.gsub(%Q(src="cid:#{cid}"), %Q(src="data:#{f.mime_type};base64,#{data}"))
        else
          body = body.gsub(%Q(src="cid:#{cid}"), %Q(src="?filename=#{CGI::escape(f.filename)}&download=#{idx}"))
        end
      end
    end

    body
  rescue => e
    write_log(e)
    fallback_body_part(part)
  end

  def secure_html_body(html, options = {})
    sanitize_html(inline_css(html), options)
  end

  def inline_css(html)
    css = Nokogiri::HTML5(html).xpath('//style').map(&:text).join("\n")
    if css.present?
      Premailer.new(html, with_html_string: true, input_encoding: 'utf-8', css_string: css).to_inline_css
    else
      html
    end
  end

  def sanitize_html(html, options = {})
    sanitize_image = false
    relaxed = Sanitize::Config::RELAXED
    html = Sanitize.document(html, Sanitize::Config.merge(relaxed,
      attributes: {
        'th' => relaxed[:attributes]['th'] + %w(bgcolor),
        'td' => relaxed[:attributes]['td'] + %w(bgcolor),
      },
      protocols: {
        'img' => { 'src' => relaxed[:protocols]['img']['src'] + %w(cid) }
      },
      css: {
        properties: relaxed[:css][:properties] - %w(position top bottom left right)
      },
      transformers: options[:show_image] ? [] : lambda do |env|
        node = env[:node]
        node_name = env[:node_name]
        if node_name == 'img' && node[:src]
          sanitize_image = true
          node[:src] = ''
        end
        if node[:style] && node[:style] =~ /url/
          sanitize_image = true
          tree = Crass.parse_properties(node[:style]).select do |prop|
            !(prop[:children] && prop[:children].any? {|c| c[:node] == :function && c[:name] == 'url' })
          end
          node[:style] = Crass::Parser.stringify(tree)
        end
      end
    ))

    html_body = Nokogiri::HTML(html).xpath('//body').inner_html
    html_body.gsub!(Nokogiri::HTML('&nbsp;').text, '&nbsp;')

    return html_body, sanitize_image
  end

  def convert_html_to_text(html)
    Premailer.new(html, with_html_string: true, input_encoding: 'utf-8').to_plain_text
  end

  def extract_address_from_mail_list(from)
    if from.match(/<(.+)>/)
      from = $1
    end
    from
  end

  def extract_addresses_from_mail_list(froms)
    froms ||= ""
    froms.split(/,/).map do |from|
      extract_address_from_mail_list(from)
    end
  end

  def valid_encoding?(encoding)
    valid_encoding_regexps.any? {|regexp| regexp =~ encoding }
  end

  def valid_encoding_regexps
    [/utf/, /unicode/, /^iso-2022-jp/, /^euc-jp$/, /^shift[-_]jis$/, /^x-sjis$/, /ascii/]
  end

  def fallback_date_field(field, format)
    return nil unless field
    field.value.present? ? Time.parse(field.value).strftime(format) : nil
  rescue => e
    nil
  end

  def fallback_text_field(field)
    return '' unless field
    decode(field.value, auto_detect: true)
  rescue => e
    "#read failed: #{e.to_s.force_encoding('utf-8')}"
  end

  def fallback_body_part(part)
    decode(part.body.raw_source, auto_detect: true)
  rescue => e
    "#read failed: #{e.to_s.force_encoding('utf-8')}"
  end

  def write_log(e)
    warn_log "#{e}\n#{e.backtrace.join("\n")}"
  rescue => e
    ''
  end
end
