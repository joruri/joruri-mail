module Mail
  class Sanitizer
    def self.adjust_semicolon(value)
      # sanitize 'name="test.txt";;'
      value = value.gsub(/;+$/, '')
    end

    def self.adjust_encoding(value)
      value.gsub(/(name|filename)\s*=\s*"([^"]+?)"\s*(;|$)/im) do |match|
        # sanitize 'name="添付ファイル名.txt"' (name is not encoded)
        param = $1
        filename = $2
        delim = $3
        next match if filename =~ /\=\?(.+)?\?[BQ]\?(.*)\?\=/im

        encoded = encode_with_charset_detection(filename)
        %Q|#{param}="#{encoded}"#{delim}|
      end
    rescue => e
      warn_log e
      value
    end

    def self.adjust_quotation(value)
      value = value.gsub(/(name|filename[\d*]*)\s*=\s*"+([^"]+?)"+(;|$)/im) do
        # sanitize 'name=""test.txt"', 'name="test.txt""'
        %Q|#{$1}="#{$2}"#{$3}|
      end
      value = value.gsub(/(name|filename[\d*]*)\s*=\s*([^"]+?)\s*(;|$)/im) do
        # sanitize 'name=test.txt'
        %Q|#{$1}="#{$2}"#{$3}|
      end
      value
    end

    def self.adjust_charset(value)
      # sanitize 'charset = utf-8'
      value.gsub(/;\s*charset\s+=\s+/i, '; charset=')
    end

    def self.adjust_mime_type(value)
      case
      when value =~ /^\s*name=(.*)$/im
        # sanitize 'name="test.txt"'
        "application/octet-stream; name=#{$1}"
      when value =~ /^\s*;\s*(.*)$/mi
        # sanitize ' ; name="test.txt"'
        "application/octet-stream; #{$1}"
      when value =~ /^\s*([^\/]+?);\s*(.*)$/mi
        # sanitize 'unknown; name="test.txt"'
        "#{$1}/unknown; #{$2}"
      else
        value
      end
    end

    def self.adjust_invalid_content_transfer_encoding(value)
      value.gsub(/\s*Content-Transfer-Encoding: 8bit\s*(;|$)/m, '')
    end

    def self.encode_with_charset_detection(string)
      #charset = NKF.guess(filename).to_s.downcase
      charset = CharlockHolmes::EncodingDetector.detect(string)[:encoding].downcase
      return string unless (Encoding.find(charset) rescue nil)
      return string if string.ascii_only? && charset !~ /^iso-2022-jp/
      Encodings.b_value_encode(string.force_encoding(charset))
    rescue
      string
    end
  end
end
