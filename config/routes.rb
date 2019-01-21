Rails.application.routes.draw do
  root to: 'home#index'
  post 'filter_source', to: 'home#filter_source'
  post 'tagging', to: 'home#tagging'
end
