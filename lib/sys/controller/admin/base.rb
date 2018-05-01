class Sys::Controller::Admin::Base < ApplicationController
  include Sys::Controller::Admin::Auth
  rescue_from ActiveRecord::RecordNotFound, with: :error_auth
  before_action :pre_dispatch
  layout  'admin/sys'

  def initialize_application
    return false unless super

    @@current_user = false
    if authenticate
      Core.user          = current_user
      Core.user.password = Util::String::Crypt.decrypt(session[PASSWD_KEY])
      Core.user_group    = current_user.groups[0]
      return true
    end
    return false
  end

  def pre_dispatch
    ## each processes before dispatch
  end

  private

  def authenticate
    return true  if logged_in?
    return false if request.env['PATH_INFO'] =~ /^\/_admin\/login/
    uri  = request.env['PATH_INFO']
    uri += "?#{request.env['QUERY_STRING']}" if request.env['QUERY_STRING'].present?
    cookies[:sys_login_referrer] = { value: uri, httponly: true }
    respond_to do |format|
      format.html { redirect_to('/_admin/login') }
      format.xml  { http_error 500, 'This is a secure page.' }
    end
    return false
  end

  def error_auth
    http_error 500, '権限がありません。'
  end
end
