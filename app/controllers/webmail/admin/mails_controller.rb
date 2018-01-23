class Webmail::Admin::MailsController < Webmail::Controller::Admin::Base
  include Sys::Controller::Scaffold::Base
  include Webmail::Admin::Mobile::Mail
  layout :select_layout

  before_action :handle_mailto_scheme, if: -> { params[:src] == 'mailto' && params[:uri] }
  before_action :check_user_email, only: [:new, :create, :edit, :update, :answer, :forward]
  before_action :check_posted_uids, only: [:move, :delete, :seen, :unseen, :junk, :downloads]

  before_action :set_conf, only: [:index, :show, :move]
  before_action :set_address_histories, only: [:index, :show, :move]
  before_action :set_mail_form_size

  before_action :set_quota, only: [:index]
  before_action :set_conditions_from_params, only: [:index, :show]
  before_action :set_sort_from_params, only: [:index, :show, :move]

  after_action :reload_mailboxes, only: [:destroy, :delete, :empty, :move, :seen, :unseen, :star, :junk]
  after_action :reload_quota, only: [:destroy, :delete, :empty, :move, :seen, :unseen, :star, :junk]

  def pre_dispatch
    return redirect_to action: :index, mailbox: params[:mailbox] if params[:reset]

    @mailboxes = Webmail::Mailbox.load_mailboxes(params[:reload].present? ? :all : nil)
    @mailbox = @mailboxes.detect { |mailbox| mailbox.name == params[:mailbox] }
    return http_error(404) unless @mailbox
  end

  def index
    last_uid, recent, delayed = Webmail::Filter.apply_recents(@mailboxes.detect(&:inbox?))
    if recent
      reload_mailboxes
      reload_quota
    end
    if @mailbox.inbox?
      @conditions += ['UID', "1:#{last_uid}"]
    end
    if delayed > 0
      flash.now[:error] = "新着メールのフィルター処理件数が規定値を超えたため、残り#{delayed}件はバックグラウンドで実行します。完了までに時間がかかる場合があります。"
    end

    @items = @mailbox.paginate_mails(conditions: @conditions, sort: @sort,
      page: params[:page], limit: @conf.mails_per_page, starred: params[:sort_starred])
  end

  def show
    @item = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'])
    return error_auth unless @item

    if params[:show_html_image]
      return http_error(404) unless @item.html_mail?
      return respond_to do |format|
        format.json { render :show_html }
      end
    end

    Core.title += " - #{@item.subject} - #{Core.current_user.email}"

    if @item.unseen?
      @mailbox.flag_mails(@item.uid, [:Seen])
      reload_mailboxes

      @item.seen!

      if @item.mdn_request_mode == :auto && !@item.mdn_sent? && !@mailbox.draft_box? && !@mailbox.sent_box?
        begin
          send_mdn_message(@item.mdn_request_mode)
        rescue => e
          flash.now[:notice] = "開封確認メールの自動送信に失敗しました。"
        end
      end
    end

    @pagination = @mailbox.paginate_mail_by_uid(params[:id], conditions: @conditions, sort: @sort,
      starred: params[:sort_starred])

    _show @item
  end

  def download
    @item = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'])
    return error_auth unless @item

    case
    when params[:download] == 'eml'
      filename = "#{@item.subject.presence || '件名なし'}.eml"
      msg = @item.rfc822
      send_data(msg, filename: filename, type: 'message/rfc822', disposition: 'attachment')
    when params[:download] == 'all'
      filename = "#{@item.filename_for_download}.zip"
      zipdata = @item.zip_attachments(encoding: request.user_agent =~ /Windows/ ? 'shift_jis' : 'utf-8')
      send_data(zipdata, type: 'application/zip', filename: filename, disposition: 'attachment')
    when params[:download]
      return download_attachment(params[:download])
    when params[:header]
      msg = @item.rfc822
      msg = msg.slice(0, msg.index("\r\n\r\n"))
      send_data(msg.gsub(/\r\n/m, "\n"), type: 'text/plain; charset=utf-8', disposition: 'inline')
    when params[:source]
      msg = @item.rfc822
      send_data(msg.gsub(/\r\n/m, "\n"), type: 'text/plain; charset=utf-8', disposition: 'inline')
    end
  end

  def download_attachment(no)
    return http_error(404) unless at = @item.attachments[no.to_i]

    if params[:thumbnail].present? && (data = at.thumbnail(self.class.helpers.attachment_thumbnail_options))
      type = 'image/jpeg'
    else
      data = at.body
      type = at.content_type
    end

    send_data(data, type: type, filename: at.name, disposition: params[:disposition].presence || at.disposition)
  end

  def new
    @item = Webmail::Mail.new
    @item.init_for_new(template: default_template, sign: default_sign)
    @item.init_from_flash(flash)
    @item.init_from_params(params)
    @item.append_mobile_notice_to_body if request.mobile? || request.smart_phone?
  end

  def create
    @item = Webmail::Mail.new(item_params)
    send_message(@item)
  end

  def edit
    @ref = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'])
    return http_error(404) unless @ref

    @item = Webmail::Mail.new(item_params)
    @item.init_for_edit(@ref, format: params[:mail_view])
    @item.init_from_flash(flash)
    @item.append_mobile_notice_to_body if request.mobile? || request.smart_phone?
    render :new
  end

  def update
    @ref = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'])
    return http_error(404) unless @ref

    @item = Webmail::Mail.new(item_params)
    send_message(@item, @ref) do
      if !params[:remain_draft] && @ref.draft?
        @mailbox.delete_mails(@ref.uid)
      end
    end
  end

  def answer
    @ref = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'])
    return http_error(404) unless @ref

    @item = Webmail::Mail.new(item_params)
    @item.reference = @ref

    if request.post?
      return send_message(@item, @ref) do
        @mailbox.flag_mails(@ref.uid, [:Answered])
      end
    end

    @item.init_for_answer(@ref, format: params[:mail_view],
      sign: default_sign,
      sign_pos: Webmail::Setting.user_config_value(:sign_position),
      all: params[:all],
      quote: params[:qt]
    )
    @item.init_from_flash(flash)
    @item.append_mobile_notice_to_body if request.mobile? || request.smart_phone?
    render :new
  end

  def forward
    @ref = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'])
    return http_error(404) unless @ref

    @item = Webmail::Mail.new(item_params)

    if request.post?
      return send_message(@item, @ref) do
        @mailbox.flag_mails(@ref.uid, ['$Forwarded'])
      end
    end

    @item.init_for_forward(@ref, format: params[:mail_view],
      sign: default_sign,
      sign_pos: Webmail::Setting.user_config_value(:sign_position)
    )
    @item.init_from_flash(flash)
    @item.append_mobile_notice_to_body if request.mobile? || request.smart_phone?
    render :new
  end

  def send_message(item, ref = nil, &block)
    config = Webmail::Setting.user_config_value(:mail_from)
    ma = Mail::Address.new
    ma.address      = Core.current_user.email
    ma.display_name = Core.current_user.name if config != "only_address"
    item.in_from = ma.to_s

    ## submit/file
    if params[:commit_file].present?
      item.save_tmp_attachments
      return render :new
    end

    ## submit/destroy
    if params[:commit_destroy].present?
      item.delete_tmp_attachments
      return redirect_to action: :close
    end

    ## submit/draft
    if params[:commit_draft].present?
      unless item.valid?(:draft)
        return render :new
      end
      return save_as_draft(item, ref, &block)
    end

    ## submit/send
    unless item.valid?(:send)
      return render :new
    end

    begin
      mail = item.prepare_mail(request)
      mail.delivery_method(:smtp, Webmail::Mail.smtp_settings(Core.current_user))
      mail.deliver
    rescue => e
      flash.now[:error] = "メールの送信に失敗しました。（#{e}）"
      respond_to do |format|
        format.html { render :action => :new }
        format.xml  { render :xml => item.errors, :status => :unprocessable_entity }
      end
      return
    end

    item.delete_tmp_attachments
    Webmail::MailAddressHistory.save_user_histories(item.in_to_addrs)

    yield if block_given?

    ## save to 'Sent'
    begin
      mail.header[:bcc].include_in_headers = true
      sent = @mailboxes.detect(&:use_as_sent?)
      Timeout.timeout(60) { Core.imap.append(sent.name, mail.to_s, [:Seen], Time.now) }
    rescue => e
      flash[:error] = "メールは送信できましたが、送信トレイへの保存に失敗しました。（#{e}）"
    end

    status         = params[:_created_status] || :created
    location       = url_for(action: :close)
    respond_to do |format|
      format.html { redirect_to(location) }
      format.xml  { render :xml => item.to_xml(:dasherize => false), :status => status, :location => location }
    end
  end

  def save_as_draft(item, ref, &block)
    begin
      mail = item.prepare_mail(request)
      mail.header[:bcc].include_in_headers = true
      flags = [:Seen, :Draft].tap { |a| a << :Flagged if ref && ref.starred? }
      draft = @mailboxes.detect(&:use_as_drafts?)
      Timeout.timeout(60) { Core.imap.append(draft.name, mail.to_s, flags, Time.now) }
    rescue => e
      flash.now[:error] = "下書き保存に失敗しました。（#{e}）"
      respond_to do |format|
        format.html { render :action => :new }
        format.xml  { render :xml => item.errors, :status => :unprocessable_entity }
      end
      return
    end

    item.delete_tmp_attachments

    yield if block_given?

    status         = params[:_created_status] || :created
    location       = url_for(action: :close)
    respond_to do |format|
      format.html { redirect_to(location) }
      format.xml  { render :xml => item.to_xml(:dasherize => false), :status => status, :location => location }
    end
  end

  def destroy
    @item = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'], fetch: ['FLAGS'])
    return error_auth unless @item

    trash = @mailboxes.detect(&:use_as_trash?)
    num = @mailbox.trash_mails(trash.name, @item.uid)

    flash[:notice] = num > 0 ? 'メールを削除しました。' : 'メールの削除に失敗しました。' unless new_window?
    redirect_to action: new_window? ? :close : :index
  end

  def move
    uids = params[:item][:ids].keys.map(&:to_i).select(&:positive?)
    return http_error if uids.blank?

    if !params[:item][:mailbox]
      @items = @mailbox.find_mails(conditions: ['UID', uids] + ['UNDELETED'], sort: @sort)
      return render template: 'webmail/admin/mails/move'
    end

    num =
      if params[:copy].present?
        @mailbox.copy_mails(params[:item][:mailbox], uids)
      else
        @mailbox.move_mails(params[:item][:mailbox], uids)
      end

    label = params[:copy].blank? ? '移動' : 'コピー'
    flash[:notice] = "#{num}件のメールを#{label}しました。" unless new_window?
    redirect_to action: new_window? ? :close : :index
  end

  def delete
    uids = params[:item][:ids].keys.map(&:to_i).select(&:positive?)
    return http_error if uids.blank?

    trash = @mailboxes.detect(&:use_as_trash?)
    num = @mailbox.trash_mails(trash.name, uids)

    flash[:notice] = "#{num}件のメールを削除しました。"
    redirect_to action: :index
  end

  def seen
    uids = params[:item][:ids].keys.map(&:to_i).select(&:positive?)
    return http_error if uids.blank?

    num = @mailbox.flag_mails(uids, [:Seen])

    flash[:notice] = "#{num}件のメールを既読にしました。"
    redirect_to action: :index
  end

  def unseen
    uids = params[:item][:ids].keys.map(&:to_i).select(&:positive?)
    return http_error if uids.blank?

    num = @mailbox.unflag_mails(uids, [:Seen])

    flash[:notice] = "#{num}件のメールを未読にしました。"
    redirect_to action: :index
  end

  def junk
    uids = params[:item][:ids].keys.map(&:to_i).select(&:positive?)
    return http_error if uids.blank?

    items = @mailbox.find_mails(conditions: ['UID', uids] + ['UNDELETED'])
    return redirect_to action: :index if items.blank?

    Webmail::Filter.register_spams(items)

    junk = @mailboxes.detect(&:use_as_junk?)
    @mailbox.move_mails(junk.name, uids)

    flash[:notice] = "#{items.count}件のメールを迷惑メールに登録しました。"
    redirect_to action: :index
  end

  def empty
    @mailboxes.reverse.each do |mailbox|
      if mailbox.trash_box?(:children)
        mailbox.delete_mailbox
      end
    end

    @mailbox.empty_mails

    flash[:notice] = 'ごみ箱を空にしました。'
    respond_to do |format|
      format.html { redirect_to action: :index }
      format.xml  { head :ok }
    end
  end

  def send_mdn
    @item = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'])
    return error_auth unless @item && @item.has_disposition_notification_to?

    if request.xhr?
      send_mdn_message(:manual)
      return render plain: ''
    else
      begin
        send_mdn_message(:manual)
        flash[:notice] = '開封確認メールを送信しました。'
      rescue => e
        flash[:notice] = '開封確認メールの送信に失敗しました。'
      end
      return redirect_to action: :show
    end
  end

  def reset_address_history
    Webmail::MailAddressHistory.where(user_id: Core.current_user.id).delete_all

    flash[:notice] = 'クイックアドレス帳をリセットしました。'
    redirect_to action: :index
  end

  def star
    @item = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'], fetch: ['FLAGS'])
    return error_auth unless @item

    if @item.starred?
      @mailbox.unflag_mails(@item.uid, [:Flagged])
    else
      @mailbox.flag_mails(@item.uid, [:Flagged])
    end

    if request.mobile?
      if params[:from] == 'list' || @mailbox.flagged_box?
        redirect_to action: :index, id: params[:id], mobile: :list
      else
        redirect_to action: :show, id: params[:id]
      end
    else
      render plain: 'OK'
    end
  end

  def label
    @item = @mailbox.find_mail_by_uid(params[:id], conditions: ['UNDELETED'], fetch: ['FLAGS'])
    return error_auth unless @item

    @label_confs = Webmail::Setting.load_label_confs

    label_id = params[:label].to_i
    labels = label_id == 0 ? (1..9).map { |id| "$label#{id}" } : ["$label#{label_id}"]

    if label_id == 0 || @item.labeled?(label_id)
      @mailbox.unflag_mails(@item.uid, labels)
      @item.flags -= labels
    else
      @mailbox.flag_mails(@item.uid, labels)
      @item.flags += labels
    end

    render layout: false
  end

  def downloads
    uids = params[:item][:ids].keys.map(&:to_i).select(&:positive?)
    return http_error if uids.blank?

    filename = "#{@mailbox.title}_#{Time.now.strftime("%Y%m%d_%H%M%S")}.zip"
    zipdata, count = @mailbox.compress_mails(uids, encoding: request.user_agent =~ /Windows/ ? 'shift_jis' : 'utf-8')
    send_data(zipdata, type: 'application/zip', filename: filename, disposition: 'attachment')
  end

  def new_window?
    params[:new_window] == '1'
  end

  private

  def select_layout
    case action_name.to_sym
    when :new, :create, :edit, :update, :answer, :forward, :close
      'admin/webmail/mail_form'
    when :show, :move
      new_window? ? 'admin/webmail/mail_form' : 'admin/webmail/base'
    else
      'admin/webmail/base'
    end
  end

  def keep_params(options = {})
    if options[:mailbox].blank? && options[:controller].blank?
      keeps = params.slice(:page, :search, :s_keyword, :s_column, :s_status, :s_label,
        :sort_key, :sort_order, :sort_starred, :new_window).permit!
      options = options.reverse_merge(keeps)
    end
    options
  end

  def handle_mailto_scheme
    mailto = Webmail::Lib::Mailto.parse(params[:uri].to_s)
    [:to, :cc, :bcc, :subject, :body].each { |k| mailto[k] = params[k] if params[k] }
    redirect_to new_webmail_mail_path(mailto.merge(mailbox: 'INBOX'))
  end

  def check_user_email
    if Core.current_user.email.blank?
      return render plain: 'メールアドレスが登録されていません。', layout: true
    end
  end

  def check_posted_uids
    if !params[:item] || !params[:item][:ids]
      return redirect_to action: :index
    end    
  end

  def item_params
    return {} unless params[:item]
    params.require(:item).permit(
      :in_to, :in_cc, :in_bcc, :in_reply_to, :in_subject, :in_body, :in_html_body,
      :in_format, :in_priority, :in_request_mdn, :in_request_dsn,
      :tmp_id, :tmp_attachment_ids => [], :in_files => []
    )
  end

  def set_conf
    @conf = Webmail::Setting.user_config_values([
      :mails_per_page, :mail_list_subject, :mail_list_from_address, :mail_refresh_interval, :mail_address_history,
      :html_mail_view, :mail_attachment_view, :mail_open_window,
      :mail_form_size,
    ])
    @conf.mails_per_page = request.mobile? ? 20 : (@conf.mails_per_page.presence || 20).to_i
    @conf.mail_address_history = (@conf.mail_address_history.presence || 10).to_i
    @conf.html_mail_view = @conf.html_mail_view.presence || 'html'
    @mail_form_size = @conf.mail_form_size.presence || 'medium'

    @conf.mail_labels = Webmail::Setting.load_label_confs
  end

  def set_address_histories
    if @conf.mail_address_history != 0 && !new_window?
      @address_histories = Webmail::MailAddressHistory.load_user_histories(@conf.mail_address_history)
    end
  end

  def set_mail_form_size
    @mail_form_size ||= Webmail::Setting.user_config_value(:mail_form_size, 'medium')
  end

  def reload_mailboxes
    @mailboxes = Webmail::Mailbox.load_mailboxes(:all)
  end

  def set_quota
    @quota = Webmail::QuotaRoot.load_quota(params[:reload].present?)
  end

  def reload_quota
    @quota = Webmail::QuotaRoot.load_quota(true)
  end

  def set_conditions_from_params
    fromto = @mailbox.sent_box? || @mailbox.draft_box? ? 'TO' : 'FROM'
    @conditions = Webmail::Mail.make_conditions_from_params(params, fromto)
  end

  def set_sort_from_params
    @sort = Webmail::Mail.make_sort_from_params(params)
  end

  def default_sign
    if !request.mobile? && !request.smart_phone?
      Webmail::Sign.default_sign
    end
  end

  def default_template
    if !request.mobile? && !request.smart_phone?
      Webmail::Template.default_template
    end
  end

  def send_mdn_message(mdn_mode)
    mdn = Webmail::Mail.new
    mdn.in_from ||= Core.current_user.email_format
    mail = mdn.prepare_mdn(@item, mdn_mode.to_s, request)
    mail.delivery_method(:smtp, Webmail::Mail.smtp_settings(Core.current_user))
    mail.deliver

    @mailbox.flag_mails(@item.uid, ['$MDNSent'])
    @item.flags << '$MDNSent'
  end

  def rescue_mail_action?
    (request.post? || request.put? || request.patch?) &&
      (action_name.in?(%w(create update answer forward mobile_send)))
  end

  def rescue_exception(e)
    return super unless rescue_mail_action?

    @mailbox = Webmail::Mailbox.where(user_id: Core.current_user.id, name: params[:mailbox] || 'INBOX').first
    return super unless @mailbox

    @item = Webmail::Mail.new(item_params)
    flash.now[:error] = "サーバーエラーが発生しました。時間をおいて再度送信してください。（#{e}）"
    render :new
  end
end
