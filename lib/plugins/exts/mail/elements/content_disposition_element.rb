module Mail
  module ContentDispositionElementFix
    def initialize(string)
      string = Sanitizer.adjust_semicolon(string)
      string = Sanitizer.adjust_encoding(string)
      string = Sanitizer.adjust_quotation(string)

      begin
        super(string)
      rescue => e
        warn e.message
        @disposition_type = 'attachment'
        @parameters = ['filename' => Mail::Sanitizer.encode_with_charset_detection(string)]
      end
    end
  end

  class ContentDispositionElement
    prepend ContentDispositionElementFix
  end
end
