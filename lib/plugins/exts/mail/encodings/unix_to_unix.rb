module Mail
  module Encodings
    class UnixToUnix < TransferEncoding
      def self.decode(str)
        # support multi-line encoded filename
        if match = str.gsub("\r\n", "\n").match(/^begin.*?\n([ \t].*?\n)*(.*)\n[ `]+\nend/m) 
          match[2].unpack('u').first
        end   
      end
    end
  end
end
