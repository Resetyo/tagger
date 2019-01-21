require "google/cloud/bigquery"

creds = Google::Cloud::Bigquery::Credentials.new JSON.parse(ENV['BIGQUERY_CREDENTIALS'])

Google::Cloud::Bigquery.configure do |config|
  config.project_id  = ENV['BIGQUERY_PROJECT']
  config.credentials = creds
end
