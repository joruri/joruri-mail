class Webmail::Address < ApplicationRecord
  include Sys::Model::Base
  include Sys::Model::Auth::Free

  NO_GROUP = 'no_group'

  attr_accessor :easy_entry

  has_many :groupings, foreign_key: :address_id, class_name: 'Webmail::AddressGrouping',
    dependent: :destroy
  has_many :groups, -> { order(:name, :id) }, through: :groupings

  validates :user_id, :name, presence: true
  validates :email, presence: true, email: { only_address: true, strict: true }
  validate :validate_email_parsing

  before_save :replace_kana

  with_options if: :easy_entry do
    validates :email, uniqueness: { scope: :user_id }
    before_validation :unquote_name
  end

  scope :search, ->(params) {
    rel = all
    params.each do |k, vs|
      next if vs.blank?
      vs.split(/[ 　]+/).each do |v|
        next if v == ''
        case k
        when 's_group_id'
          rel = rel.where(group_id: v == NO_GROUP ? nil : v)
        when 's_name'
          rel = rel.where(arel_table[:name].matches("%#{escape_like(v)}%"))
        when 's_email'
          rel = rel.where(arel_table[:email].matches("%#{escape_like(v)}%"))
        when 's_name_or_kana'
          kana_v = v.to_s.tr("ぁ-ん", "ァ-ン")
          rel = rel.where([
            arel_table[:name].matches("%#{escape_like(v)}%"),
            arel_table[:kana].matches("%#{escape_like(kana_v)}%"),
          ].reduce(:or))
        end
      end
    end
    rel
  }

  def email_format
    "#{Email.quote_phrase(name)} <#{email}>"
  end

  def editable?
    Core.user.has_auth?(:manager) || user_id == Core.user.id
  end

  def deletable?
    Core.user.has_auth?(:manager) || user_id == Core.user.id
  end

  def sorted_groups
    self.groups.sort do |g1, g2|
      names1 = g1.ancestors.map(&:name)
      names2 = g2.ancestors.map(&:name)
      comp = 0
      (0..([names1.size, names2.size].max - 1)).each do |i|
        comp = names1[i].to_s <=> names2[i].to_s
        break if comp != 0
      end
      comp
    end
  end

  private

  def validate_email_parsing
    if name.present? && email.present? && errors.blank?
      unless Email.parse(email_format)
        errors.add(:name, "またはメールアドレスに使用できない文字が含まれています。（#{email_format}）")
      end
    end
  end

  def unquote_name
    self.name = Email.unquote(name) if name.present?
  end

  def replace_kana
    to_kana = lambda {|str| str.to_s.tr("ぁ-ん", "ァ-ン") }
    self.kana = to_kana.call(kana) if kana.present?
    self.company_kana = to_kana.call(company_kana) if company_kana.present?
  end

  class << self
    def to_csv(items)
      CSV.generate(encoding: 'utf-8', force_quotes: true) do |csv|
        csv <<  [
          '表示名', 'フリガナ', '並び順', '電子メール アドレス', '自宅の郵便番号', '自宅の住所',
          '自宅電話番号 :', '自宅ファックス', '携帯電話 ', '個人 Web ページ',
          '勤務先の郵便番号', '勤務先の住所', '勤務先電話番号',
          '勤務先ファックス', '会社名', '会社名フリガナ', '役職', 'メモ'
        ]
        items.each do |item|
          csv << [
            item.name,               #表示名
            item.kana,               #フリガナ
            item.sort_no,            #並び順
            item.email,              #電子メールアドレス
            item.zip_code,           #自宅の郵便番号
            item.address,            #自宅の住所
            item.tel,                #自宅電話番号
            item.fax,                #自宅ファックス
            item.mobile_tel,         #携帯電話
            item.uri,                #個人 Web ページ
            item.company_zip_code,   #勤務先の郵便番号
            item.company_address,    #勤務先の住所
            item.company_tel,        #勤務先電話番号
            item.company_fax,        #勤務先ファックス
            item.company_name,       #会社名
            item.company_kana,       #会社名フリガナ
            item.official_position,  #役職
            item.memo,               #メモ
          ] 
        end
      end
    end

    def from_csv(csv)
      items = []
      CSV.parse(csv, headers: true) do |data|
        item = self.new(
          user_id:           Core.user.id,
          name:              data['表示名'].presence || [data['姓'], data['ミドル ネーム'], data['名']].join(' '),
          kana:              data['フリガナ'],
          sort_no:           data['並び順'],
          email:             data['電子メール アドレス'],
          zip_code:          data['自宅の郵便番号'],
          address:           data['自宅の住所'].presence || [data['自宅の都道府県'], data['自宅の市区町村'], data['自宅の番地']].join,
          tel:               data['自宅電話番号 :'],
          fax:               data['自宅ファックス'],
          mobile_tel:        data['携帯電話 '],
          uri:               data['個人 Web ページ'],
          company_zip_code:  data['勤務先の郵便番号'],
          company_address:   data['勤務先の住所'].presence || [data['勤務先の都道府県'], data['勤務先の市区町村'], data['勤務先の番地']].join,
          company_tel:       data['勤務先電話番号'],
          company_fax:       data['勤務先ファックス'],
          company_name:      data['会社名'],
          company_kana:      data['会社名フリガナ'],
          official_position: data['役職'],
          memo:              data['メモ']
        )
        item.valid?
        items << item
      end
      items
    end

    private

    def split_address(address)
      pref_regexp = ".+[都|道|府|県]"
      city_regexp = ".+[市|区|町|村]"
      addr = address.to_s
      if (match = addr.scan(/(#{pref_regexp})(#{city_regexp})(.*)/)) && match[0] && match[0].length == 3
        match[0]
      elsif (match = addr.scan(/(#{city_regexp})(.*)/)) && match[0] && match[0].length == 2
        ['', match[0][0], match[0][1]]
      else
        ['', '', addr]
      end
    end
  end
end
