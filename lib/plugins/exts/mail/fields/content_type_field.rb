module Mail
  module ContentTypeFieldFix
    def parameters
      ret = super
      @parameters.delete("charset") if @parameters.key?("boundary") || @parameters.key?("name")
      ret
    end
  end
  class ContentTypeField < StructuredField
    prepend ContentTypeFieldFix
  end
end
