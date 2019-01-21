module HomeHelper
  def to_url str
    'https://' + str unless str.match(/^(http:|https:)/)
  end
end
