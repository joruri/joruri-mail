class System::ProductSynchro < System::Database
  include Sys::Model::Base
  include Sys::Model::Base::Config
  include Sys::Model::Auth::Manager

  belongs_to :product, class_name: 'System::Product', foreign_key: :product_id

  def execute
    # 中間データ作成
    return unless self.copy_ldap_temporary
    # バックアップ
    return unless self.backup_table
    # 同期
    self.synchronize
  end

  private

  def copy_ldap_temporary
    update_attributes(state: 'temp')
    
    @results = { group: 0, gerr: 0, user: 0, uerr: 0 }

    root = make_root_temporaries(version)

    task = Sys::LdapSynchroTask.new(version: version, target_tenant_code: root.tenant_code)
    unless task.save
      update_attributes(state: 'failure')
      return false
    end

    unless root.save(validate: false)
      update_attributes(state: 'failure')
      return false
    end

    groups = System::LdapTemporary.where(version: version, parent_id: 0, data_type: 'group').order(:sort_no, :code)
    groups.each { |group| copy_ldap_temporaries(group, root) }

    task.fetch_log = Sys::LdapSynchroTask.make_fetch_log(@results)
    task.save

    messages = []
    messages << "グループ #{@results[:group]}件"
    messages << "-- 失敗 #{@results[:gerr]}件" if @results[:gerr] > 0
    messages << "ユーザー #{@results[:user]}件"
    messages << "-- 失敗 #{@results[:uerr]}件" if @results[:uerr] > 0
    update_attributes(remark_temp: messages.join("\n"))

    if @results[:gerr] > 0 || @results[:uerr] > 0
      update_attributes(state: 'failure')
      return false
    end

    return true
  end

  def backup_table
    update_attributes(state: 'back')

    results = { copy: 0, cerr: 0 }

    [:sys_users, :sys_groups, :sys_users_groups].each do |table|
      begin
        ApplicationRecord.copy_table("#{table}", "#{table}_backups")
        results[:copy] += 1
      rescue => e
        results[:cerr] += 1
      end
    end

    messages = []
    messages << "テーブル #{results[:copy]}件"
    messages << "--失敗 #{results[:cerr]}件" if results[:cerr] > 0
    update_attributes(remark_back: messages.join("\n"))

    if results[:cerr] > 0
      update_attributes(state: 'failure')
      return false
    end

    return true
  end

  def synchronize
    update_attributes(state: 'sync')

    task = Sys::LdapSynchroTask.find_by!(version: version)
    task.synchronize
    results = task.synchro_results

    messages = []
    messages << "グループ"
    messages << "-- 更新 #{results[:group]}件"
    messages << "-- 削除 #{results[:gdel]}件" if results[:gdel] > 0
    messages << "-- 失敗 #{results[:gerr]}件" if results[:gerr] > 0
    messages << "ユーザー"
    messages << "-- 更新 #{results[:user]}件"
    messages << "-- 削除 #{results[:udel]}件" if results[:udel] > 0
    messages << "-- 失敗 #{results[:uerr]}件" if results[:uerr] > 0
    update_attributes(remark_sync: messages.join("\n"))

    if results[:gerr] > 0 || results[:uerr] > 0
      update_attributes(state: 'failure')
      return false
    else
      update_attributes(state: 'success')
      return true
    end
  end

  def make_root_temporaries(version)
    root = Sys::Group.find_by!(level_no: 1, ldap: 1)

    sg                = Sys::LdapSynchro.new
    sg.tenant_code    = root.tenant_code
    sg.parent_id      = 0
    sg.version        = version
    sg.entry_type     = 'group'
    sg.code           = root.code
    sg.name           = root.name
    sg.name_en        = root.name_en
    sg.email          = root.email
    sg.sort_no        = root.sort_no
    sg.group_s_name   = root.group_s_name
    sg
  end

  def copy_ldap_temporaries(group, parent)
    ## group
    sg                = Sys::LdapSynchro.new
    sg.tenant_code    = parent.tenant_code
    sg.parent_id      = parent.id
    sg.version        = group.version
    sg.entry_type     = group.data_type
    sg.code           = group.code
    sg.name           = group.name
    sg.name_en        = group.name_en
    sg.email          = group.email
    sg.kana           = group.kana
    sg.sort_no        = group.sort_no
    sg.official_position = group.official_position
    sg.assigned_job   = group.assigned_job
    sg.group_s_name   = group.group_s_name

    if sg.save(validate: false)
      @results[:group] += 1
    else
      @results[:gerr] += 1
      return false
    end

    ## users
    group.ldap_users.each do |user|
      su                = Sys::LdapSynchro.new
      su.tenant_code    = parent.tenant_code
      su.parent_id      = sg.id
      su.version        = user.version
      su.entry_type     = user.data_type
      su.code           = user.code
      su.name           = user.name
      su.name_en        = user.name_en
      su.email          = user.email
      su.kana           = user.kana
      su.sort_no        = user.sort_no
      su.official_position = user.official_position
      su.assigned_job   = user.assigned_job
      su.group_s_name   = user.group_s_name
      
      if su.save
        @results[:user] += 1
      else
        @results[:uerr] += 1
      end
    end

    ## next
    group.ldap_children.each { |g| copy_ldap_temporaries(g, sg) }
  end

  class << self
    def check
      item = System::ProductSynchro.joins(:product)
        .where('system_products.product_type = ?', 'mail')
        .where(state: 'start')
        .order(:created_at).first
      item.execute if item
    end
  end
end
