class Webmail::Setting < ApplicationRecord
  include Sys::Model::Base
  include Sys::Model::Auth::Free

  @@label_max_count = 9
  cattr_accessor :label_max_count
  @@switch_user_max_count = Joruri.config.application['webmail.switch_user_max_count'].to_i
  cattr_accessor :switch_user_max_count

  class Category < ActiveHash::Base
    include ActiveHash::Associations
    fields :name, :title

    attr_accessor :settings
    has_many :configs, class_name: 'Webmail::Setting::Config', primary_key: :name, foreign_key: :category_name

    def self.add(name, options = {})
      super(options.reverse_merge(
        name: name,
        title: I18n.t("webmail.setting.categories.#{name}", default: '')
      ))
    end

    add :mail_list
    add :mail_detail
    add :mail_form
    add :mail_label
    add :sys_address
    add :address
    add :mobile
    add :switch_user if Webmail::Setting.switch_user_max_count > 0
  end

  class Config < ActiveHash::Base
    include ActiveHash::Associations
    fields :category_name, :name, :title, :form_type, :data_type, :options, :default, :crypt_fields, :lower_text

    belongs_to :category, class_name: 'Webmail::Setting::Category', primary_key: :name, foreign_key: :category_name

    def self.add(category_name, name, options = {})
      super(options.reverse_merge(
        category_name: category_name,
        name: name,
        title: '',
        form_type: :select,
        data_type: :string,
        default: '',
        lower_text: I18n.t("webmail.setting.configs.#{name}.lower_text_html", default: '')
      ))
    end

    add :mail_list, :mails_per_page, title: 'メール表示件数',
      options: [['20件（標準）',''],['30件','30'],['40件','40'],['50件','50']]
    add :mail_list, :mail_list_subject, title: '件名',
      options: [['１行で表示（標準）', ''], ['折り返して表示', 'wrap']]
    add :mail_list, :mail_list_from_address, title: '差出人のメールアドレス',
      options: [['表示する（標準）', ''], ['表示しない', 'omit_address']]
    add :mail_list, :mail_address_history, title: 'クイックアドレス帳',
      options: [['表示しない', '0'], ['5件表示', '5'], ['10件表示（標準）', ''], ['15件表示', '15'], ['20件表示', '20']]
    add :mail_list, :mail_refresh_interval, title: '画面自動更新',
      options: [['使用しない（標準）', ''], ['5分', '5'], ['10分', '10'], ['20分', '20'], ['30分', '30']]
    add :mail_detail, :html_mail_view, title: 'HTMLメールの表示',
      options: [['HTML形式で表示する（標準）', ''], ['テキスト形式で表示する', 'text']]
    add :mail_detail, :mail_attachment_view, title: '添付ファイルの表示',
      options: [['画像をサムネイル形式で表示する（標準）', ''], ['一覧形式で表示する', 'list']]
    add :mail_detail, :mail_open_window, title: 'メールの表示方法',
      options: [['同じウィンドウで開く（標準）', ''], ['新しいウィンドウで開く', 'new_window']]
    add :mail_form, :mail_from, title: 'メール送信者名',
      options: [['氏名（標準）',''],['メールアドレスのみ','only_address']]
    add :mail_form, :mail_form_size, title: 'ウィンドウサイズ',
      options: [['小','small'],['中（標準）',''],['大','large']]
    add :mail_form, :mail_encoding, title: '文字エンコーディング',
      options: [['Unicode (UTF-8)','utf-8'],['日本語 (ISO-2022-JP)','']]
    add :mail_form, :sign_position, title: '署名の位置（返信・転送時）',
      options: [['引用文の前（標準）', ''], ['引用文の後', 'bottom']]
    #add :mail_form, :attachment_check, title: '添付忘れ確認',
    #  options: [['確認しない（標準）', ''], ['確認する', '1']]
    #add :mail_form, :attachment_check_keywords, title: '添付忘れ確認キーワード', form_type: :text_area,
    #  default: "attach\nattachment\nattaching\n添付\n同封\n別添"
    #add :mail_form, :forward, title: '転送先アドレス', form_type: :text_field
    add :sys_address, :sys_address_order, title: '並び順',
      options: [['メールアドレス（標準）', ''], ['名前', 'name'], ['フリガナ', 'kana'], ['役職（担当順）', 'sort_no']]
    add :address, :address_order, title: '並び順',
      options: [['メールアドレス（標準）', ''], ['フリガナ', 'kana'], ['並び順指定', 'sort_no']]
    add :mobile, :mobile_access, title: 'モバイルアクセス',
      options: [['不許可（標準）', '0'], ['許可', '1']], default: '0'
    add :mobile, :mobile_password, title: 'モバイルパスワード', form_type: :password_field
    add :mail_label, :label1, title: 'ラベル1', form_type: :label_color_field, data_type: :json,
      default: { id: '1', name: '重要', color: '#ff0000', state: 'enabled' }
    add :mail_label, :label2, title: 'ラベル2', form_type: :label_color_field, data_type: :json,
      default: { id: '2', name: '未処理', color: '#ff007f', state: 'enabled' }
    add :mail_label, :label3, title: 'ラベル3', form_type: :label_color_field, data_type: :json,
      default: { id: '3', name: '作業中', color: '#4444ff', state: 'enabled' }
    add :mail_label, :label4, title: 'ラベル4', form_type: :label_color_field, data_type: :json,
      default: { id: '4', name: '作業終了', color: '#008f00', state: 'enabled' }
    add :mail_label, :label5, title: 'ラベル5', form_type: :label_color_field, data_type: :json,
      default: { id: '5', name: 'ToDo', color: '#8f8f00', state: 'enabled' }
    add :mail_label, :label6, title: 'ラベル6', form_type: :label_color_field, data_type: :json,
      default: { id: '6', name: 'その他1', color: '#8f3f00', state: 'enabled' }
    add :mail_label, :label7, title: 'ラベル7', form_type: :label_color_field, data_type: :json,
      default: { id: '7', name: 'その他2', color: '#008f8f', state: 'enabled' }
    add :mail_label, :label8, title: 'ラベル8', form_type: :label_color_field, data_type: :json,
      default: { id: '8', name: 'その他3', color: '#5f005f', state: 'enabled' }
    add :mail_label, :label9, title: 'ラベル9', form_type: :label_color_field, data_type: :json,
      default: { id: '9', name: 'その他4', color: '#777777', state: 'enabled' }

    Webmail::Setting.switch_user_max_count.times do |i|
      add :switch_user, :"switch_user#{i+1}", title: "切替ユーザー#{i+1}", form_type: :account_password_field, data_type: :json,
        default: { account: nil, password: nil }, crypt_fields: [:password]
    end

    def display_value(decoded)
      case form_type
      when :select
        options.rassoc(decoded.to_s).try(:first)
      when :password_field
        decoded.to_s.gsub(/./, '*')
      when :account_password_field
        decoded[:account]
      when :label_color_field
        decoded[:name]
      else
        decoded.presence
      end
    end

    def encode(decoded)
      case data_type
      when :json
        decoded = {} if decoded.blank?
        decoded = clear_if_required_field_is_blank(decoded)
        decoded = encrypt_field(decoded)
        decoded.to_json
      else
        decoded.to_s
      end
    end

    def clear_if_required_field_is_blank(decoded)
      case form_type
      when :account_password_field
        decoded = {} if decoded[:account].blank?
      when :label_color_field
        decoded = {} if decoded[:name].blank?
      end
      decoded
    end

    def decode(encoded)
      case data_type
      when :json
        encoded = '{}' if encoded.blank?
        decoded = JSON.parse(encoded).with_indifferent_access
        decoded = default if decoded.blank?
        decrypt_field(decoded)
      else
        encoded.to_s
      end
    end

    private

    def encrypt_field(decoded)
      if crypt_fields.present?
        crypt_fields.each do |field|
          decoded[field] = Util::String::Crypt.encrypt_with_mime(decoded[field]) if decoded[field].present?
        end
      end
      decoded
    end

    def decrypt_field(decoded)
      if crypt_fields.present?
        crypt_fields.each do |field|
          decoded[field] = Util::String::Crypt.decrypt_with_mime(decoded[field]).force_encoding('utf-8') if decoded[field].present?
        end
      end
      decoded
    end

    class << self
      def label_config_names
        (1..Webmail::Setting.label_max_count).map { |i| :"label#{i}" }
      end

      def switch_user_config_names
        (1..Webmail::Setting.switch_user_max_count).map { |i| :"switch_user#{i}" }
      end
    end
  end

  validates :user_id, :name, presence: true
  validates :value, inclusion: Config.find_by(name: :address_order).options.map(&:last),
    if: lambda {|item| item.name == 'address_order' }
  validates :value, inclusion: Config.find_by(name: :sys_address_order).options.map(&:last),
    if: lambda {|item| item.name == 'sys_address_order' }

  def initialize(attributes = nil)
    super
    if name
      case name.to_sym
      when :mobile_access
        self.value = Core.user.mobile_access.to_s
      when :mobile_password
        self.value = Core.user.mobile_password
      end
    end
    self
  end

  def save(*args)
    case name.to_sym
    when :mobile_access, :mobile_password
      save_mobile_settings
      save_mobile_settings_to_gw
      errors.blank?
    else
      super
    end
  end

  def config
    @config ||= Config.find_by(name: name.to_sym) || Config.new(name: name.to_sym)
  end

  def display_value
    config.display_value(decoded_value)
  end

  def decoded_value
    @decoded_value ||= config.decode(value)
  end

  def decoded_value=(value)
    @decoded_value = value
    self.value = config.encode(value)
  end

  def editable?
    Core.user.has_auth?(:manager) || user_id == Core.user.id
  end

  def deletable?
    Core.user.has_auth?(:manager) || user_id == Core.user.id
  end

  private

  def save_mobile_settings
    if user = Sys::User.find_by(id: Core.user.id)
      self.class.save_mobile_setting_for_user(user, self)
    end
  end

  def save_mobile_settings_to_gw
    return if Joruri.config.application['webmail.synchronize_mobile_setting'].to_i != 1

    if user = System::User.find_by(code: Core.user.account)
      self.class.save_mobile_setting_for_user(user, self)
    end
  rescue => e
    errors.add(:base, "グループウェアへの設定保存に失敗しました。（#{e}）")
  end

  class << self
    def user_categorized_settings
      items = self.where(user_id: Core.user.id).index_by { |item| item.name.to_sym }
      categories = Category.all
      categories.each do |category|
        category.settings = []
        category.configs.each do |config|
          item = items[config.name] || self.new(user_id: Core.user.id, name: config.name, value: config.encode(config.default))
          category.settings << item
        end
      end
      categories
    end

    def user_setting(name)
      config = Config.find_by(name: name.to_sym)
      self.where(user_id: Core.user.id, name: name).first_or_initialize(value: config.encode(config.default))
    end

    def user_config_value(name, nullif = nil)
      if setting = user_setting(name)
        return setting.value if setting.value.present?
      end
      nullif
    end

    def user_config_values(names)
      values = self.select(:name, :value).where(user_id: Core.user.id, name: names).map do |setting|
        [setting.name.to_sym, setting.decoded_value]
      end
      ActiveSupport::OrderedOptions[*values.flatten]
    end

    def load_address_orders
      [user_config_value(:address_order, 'email'), 'id']
    end

    def load_sys_address_orders
      [user_config_value(:sys_address_order, 'email'), 'account']
    end

    def load_label_confs
      names = Config.label_config_names
      confs = self.user_config_values(names)
      confs = names.map { |name| OpenStruct.new(confs[name] || Config.find_by(name: name).default) }
      confs.select { |conf| conf.state == 'enabled' }
    end

    def load_switch_users
      names = Config.switch_user_config_names
      confs = self.user_config_values(names).values.select { |conf| conf[:account].present? }

      users = Sys::User.where(account: confs.map { |conf| conf[:account] })
      users.each do |user|
        if conf = confs.detect { |conf| conf[:account] == user.account }
          user.password = conf[:password]
        end
      end
      [Core.user] + users
    end

    def save_mobile_setting_for_user(user, item)
      user[item.name.to_sym] = item.value
      unless user.save
        user.errors.full_messages.to_a.each { |msg| item.errors.add(:base, msg) }
      end
    end
  end
end
