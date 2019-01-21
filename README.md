# README

BigQuery project_id is placed in `config/initializers/bigquery.rb`

You can set `manual_dataset` and `manual_table` variables for BigQuery otherwise the first will be used.

## Development

BigQuery credentials are placed in `config/application.yml` in `BIGQUERY_CREDENTIALS` variable as stringified JSON file.

Then:

`bundle`

`rails db:migrate`

`rails s`

### Heroku

`heroku config:set BIGQUERY_PROJECT="project name" BIGQUERY_CREDENTIALS="stringified JSON"`