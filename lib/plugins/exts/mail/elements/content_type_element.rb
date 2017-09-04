module Mail
  module ContentTypeElementFix
    def initialize(string)
      string = Sanitizer.adjust_semicolon(string)
      string = Sanitizer.adjust_encoding(string)
      string = Sanitizer.adjust_quotation(string)
      string = Sanitizer.adjust_mime_type(string)
      string = Sanitizer.adjust_charset(string)
      string = Sanitizer.adjust_invalid_content_transfer_encoding(string)

      begin
        super(string)
      rescue => e
        warn e.message
        fallback_content_type(e.value)
      end
    end

    def fallback_content_type(value)
      if value =~ %r{^([^/]+?)/([^/]+?);\s*name\s*=\s*(.+)$}im
        # matches to 'text/plain; name=***'
        @main_type = $1
        @sub_type = $2
        @parameters = ['name' => Mail::Sanitizer.encode_with_charset_detection($3)]
      elsif value =~ %r{^([^/]+?)/([^/]+?)(;|$)}im
        # matches to 'text/plain' without name parameter
        @main_type = $1
        @sub_type = $2
      else
        @main_type = 'application'
        @sub_type = 'unknown'
        @parameters = ['name' => Mail::Sanitizer.encode_with_charset_detection(value)]
      end
    rescue
      @main_type = 'application'
      @sub_type = 'unknown'
      @parameters = ['name' => Mail::Sanitizer.encode_with_charset_detection(value)]
    end
  end

  class ContentTypeElement
    prepend ContentTypeElementFix
  end
end
