module Mail
  class DispositionNotificationToField < Mail::StructuredField
    include Mail::CommonAddress

    FIELD_NAME = 'disposition-notification-to'
    CAPITALIZED_FIELD = 'Disposition-Notification-To'

    def initialize(value = nil, charset = 'utf-8')
      self.charset = charset
      super(CAPITALIZED_FIELD, value, charset)
      self.parse
      self
    end

    def encoded
      do_encode(CAPITALIZED_FIELD)
    end

    def decoded
      do_decode
    end
  end
  class DispositionNotificationToField < Mail::StructuredField
    include FieldWithIso2022JpEncoding
  end
end
