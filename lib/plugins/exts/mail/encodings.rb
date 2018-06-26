module Mail
  module Encodings
    def Encodings.value_decode(str)
      # Optimization: If there's no encoded-words in the string, just return it
      return str unless str =~ ENCODED_VALUE

      lines = collapse_adjacent_encodings(str)

      # patch start: chunk lines with same encoding
      lines = lines.chunk { |value| !!(value =~ ENCODED_VALUE) }.map { |_, array| array.join }
      lines = lines.map do |line|
        if line =~ FULL_ENCODED_VALUE
          values = line.split(FULL_ENCODED_VALUE).select(&:present?)
          values.chunk { |value| value =~ ENCODED_VALUE; $1 }
                .map { |ch, arr| { charset: ch, content: arr.join } }
        else
          [{charset: 'utf-8', content: line}]
        end
      end.flatten
      # patch end

      # Split on white-space boundaries with capture, so we capture the white-space as well
      lines.map do |line|
        # patch start: decode charset after decoding qb values
        if line[:content] =~ ENCODED_VALUE
          bytes = decode_qb_values(line[:content])
          decode_charset_from_bytes(bytes, line[:charset])
        else
          line[:content]
        end
        # patch end
      end.join
    end

    def Encodings.decode_qb_values(line)
      line.scan(/\=\?([^?]+)\?([QB])\?([^?]*?)\?\=/mi).map do |_, enc, str|
        case enc
        when *B_VALUES then str.unpack('m').first
        when *Q_VALUES then str.gsub(/_/, '=20').unpack('M').first
        end
      end.join
    end

    def Encodings.decode_charset_from_bytes(bytes, charset)
      Mail::Ruby19.transcode_charset(bytes, charset, 'utf-8')
    rescue Encoding::UndefinedConversionError, ArgumentError, Encoding::ConverterNotFoundError
      warn "Encoding conversion failed #{$!}"
      bytes.dup.force_encoding(Encoding::UTF_8).encode(Encoding::UTF_8, undef: :replace, invalid: :replace)
    end
  end
end
