class Sys::Lib::Mail::Inline
  attr_accessor :seqno
  attr_accessor :content_type
  attr_accessor :text_body
  attr_accessor :html_body
  attr_accessor :alternative
  attr_accessor :attachment
  
  def initialize(attributes = {})
    attributes.each {|name, value| instance_variable_set("@#{name}", value) }
  end

  def alternative?
    @alternative
  end
  
  def attachment?
    @attachment
  end

  def display_as_html?
    (alternative? && html_body.present?) || content_type == 'text/html'
  end
end
