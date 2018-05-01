module Joruri
  def self.version
    "2.1.5.rc1"
  end
  
  def self.default_config
    { "application" => {
        "sys.session_expiration"                 => 24,
        "sys.session_expiration_for_mobile"      => 1,
        "sys.force_site"                         => "",
        "webmail.mailbox_quota_alert_rate"       => 0.85,
        "webmail.attachment_file_max_size"       => 5,
        "webmail.attachment_file_upload_method"  => 'auto',
        "webmail.show_only_ldap_user"            => 1,
        "webmail.filter_condition_max_count"     => 100,
        "webmail.filter_max_mail_count_at_once"  => 500,
        "webmail.mail_address_history_max_count" => 100,
        "webmail.synchronize_mobile_setting"     => 0,
        "webmail.show_gw_schedule_link"          => 1,
        "webmail.mail_cache_expiration"          => 6,
        "webmail.thumbnail_width"                => 128,
        "webmail.thumbnail_height"               => 96,
        "webmail.thumbnail_quality"              => 50,
        "webmail.thumbnail_method"               => 'thumbnail',
        "webmail.thumbnail_max_size"             => 10
    }}
  end
  
  def self.config
    $joruri_config ||= {}
    Joruri::Config
  end
  
  class Joruri::Config
    def self.application
      return $joruri_config[:application] if $joruri_config[:application]
      config = Joruri.default_config["application"]
      file   = "#{Rails.root}/config/application.yml"
      if ::File.exist?(file)
        yml = YAML.load_file(file)
        yml.each do |mod, values|
          values.each do |key, value|
            config["#{mod}.#{key}"] = value unless value.nil?
          end if values
        end if yml
      end
      $joruri_config[:application] = config
    end
    
    def self.imap_settings
      $joruri_config[:imap_settings]
    end
    
    def self.imap_settings=(config)
      $joruri_config[:imap_settings] = config
    end
    
    def self.sso_settings
      $joruri_config[:sso_settings]
    end
    
    def self.sso_settings=(config)
      $joruri_config[:sso_settings] = config
    end
  end
end