class CurrentState < ApplicationRecord
  enum filter_type: [:new_domains, :all_domains]
end
