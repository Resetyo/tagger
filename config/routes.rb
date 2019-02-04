Rails.application.routes.draw do
  root to: 'home#index'
  post 'filter_source', to: 'home#filter_source'
  post 'tagging', to: 'home#tagging'
  post 'add_domains_form', to: 'home#add_domains_form'
  get 'report', to: 'home#report'
  get 'add_domains', to: 'home#add_domains'
end
