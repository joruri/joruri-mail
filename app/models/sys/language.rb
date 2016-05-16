class Sys::Language < ActiveRecord::Base
  include Sys::Model::Base
  include Sys::Model::Base::Config
  include Sys::Model::Auth::Manager

  belongs_to_active_hash :status, foreign_key: :state, class_name: 'Sys::Base::Status'

  validates :state, :name, :title, presence: true

  def states
    [['有効','enabled'],['無効','disabled']]
  end
end
