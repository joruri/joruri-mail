Joruri::Application.routes.draw do
  get 'webmail' => 'webmail/admin/mails#index', defaults: { mailbox: 'INBOX' }

  namespace 'webmail' do
    scope module: 'admin' do
      resources :siteinfo, only: :index
      resources :mails, path: '*mailbox/mails' do
        collection do
          get :empty, :close, :reset_address_history, :star, :label
          post :move, :delete, :seen, :unseen, :junk, :downloads, :mobile_manage
        end
        member do
          get :edit, :download, :answer, :forward
          post :edit, :answer, :forward, :send_mdn, :mobile_send
        end
      end
      post '*mailbox/mails/new' => 'mails#new'
      resources :mail_attachments
      resources :servers do
        collection do
          post :status
        end
      end
      resources :mailboxes, path: '*mailbox/mailboxes' do
        collection do
          patch :update
          delete :destroy
        end
      end
      resources :sys_addresses do
        member do
          get :child_groups, :child_users, :create_mail
        end
        collection do
          post :mobile_manage
        end
      end
      resources :addresses do
        collection do
          get :import, :export
          post :candidate_import, :exec_import, :export
        end
        member do
          get :create_mail
        end
      end
      resources :address_groups do
        collection do
          post :create_mail, :mobile_manage
        end
      end
      resources :filters do
        member do
          get :apply
          post :apply
        end
      end
      resources :templates
      resources :signs
      resources :memos
      resources :tools do
        collection do
          get :batch_delete
          post :batch_delete
        end
      end
      resources :settings, path: ':category/settings'
      resources :docs
      namespace :address_selector do
        post :parse_address
        resources :sys_addresses, only: [:index, :show]
        resources :addresses, only: [:index, :show]
      end
      namespace :mobile do
        get :users
      end
    end
  end

  match '_admin/gw/webmail/:mailbox/mails/new' => 'webmail/admin/mails#new', via: [:get, :post]

  scope '_api' do
    namespace 'webmail' do
      scope module: 'admin' do
        get 'unseen' => 'api#unseen'
        get 'recent' => 'api#recent'
      end
    end
  end

  get '_api/gw/webmail/unseen' => 'webmail/admin/api#unseen'
  get '_api/gw/webmail/recent' => 'webmail/admin/api#recent'
end
