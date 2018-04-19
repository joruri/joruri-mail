Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  root 'webmail/admin/mails#index', mailbox: 'INBOX'

  ## Admin
  match '_admin'                   => 'webmail/admin/mails#index', mailbox: 'INBOX', via: :get
  match '_admin/login(.:format)'   => 'sys/admin/account#login', via: [:get, :post], as: :admin_login
  match '_admin/logout(.:format)'  => 'sys/admin/account#logout', via: [:get, :post], as: :admin_logout
  match '_admin/account(.:format)' => 'sys/admin/account#info', via: :get
  match '_admin/sso'               => 'sys/admin/account#sso', via: [:get, :post]
  match '_admin/air_login'         => 'sys/admin/air#old_login', via: :get
  match '_admin/air_sso'           => 'sys/admin/air#login', via: [:get, :post]
  match '_admin/cms'               => 'sys/admin/front#index', via: :get
  match '_admin/sys'               => 'sys/admin/front#index', via: :get

  ## Modules
  Dir::entries("#{Rails.root}/config/modules").each do |mod|
    next if mod =~ /^\.+$/
    file = "#{Rails.root}/config/modules/#{mod}/routes.rb"
    load(file) if FileTest.exist?(file)
  end

  ## Exception
  match '404.:format' => 'exception#index', via: :get
  match '*path'       => 'exception#index', via: [:get, :post, :put, :patch, :delete, :options]
end
