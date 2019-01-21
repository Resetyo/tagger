class HomeController < ApplicationController
  include HomeHelper
  # require 'capybara/rails'

  def index
    @segments = ['Sports', 'Gaming ', 'Outdoor', 'Fitness', 'Comedy', 'Special Interest', 'Faith', 'News & Politics', 'Personality', 'Lifestyle', 'Kids & Family', 'Music', 'TV & Film', 'Education', 'Subscription Commerce', 'Corporate', 'Events', 'Agency', 'Other']
    @content_types = ['Episodic', 'Long form', 'Short form', 'Broadcast (linear)', 'Live streaming (event based)', 'Audio (podcast)']

    unless set_bq_vars
      @sources = []
      flash[:alert] = "Can't find any table in dataset" unless @table
      flash[:alert] = "Can't find dataset" unless @dataset
      return
    end

    current = CurrentState.first_or_create(
                domain: @table.data[0][@domain_header],
                domain_source: @table.data[0][@source_header])
    domains = []
    @sources = []

    @table.data.all.each do |row|
      @sources << row[@source_header]

      next if current.filter_type == 'new_domains' && row[@table.headers[5]].present?
      next if current.filter_source.present? && current.filter_source != row[@source_header]

      domains << [row[@domain_header], row[@source_header]]
    end

    @sources.uniq!

    unless domains.index([current&.domain, current&.domain_source])
      current.update_attributes(
          domain: domains[0][0], 
          domain_source: domains[0][1])
    end

    @domain = current&.domain
    @source = current&.domain_source
    @filter_type = current&.filter_type || :new_domains
    @filter_source = current&.filter_source
    @sites_left = domains.count -  domains.index([@domain, @source]) - 1

    if domains.count > domains.index([@domain, @source]) + 1
      @next_domain = domains[domains.index([@domain, @source]) + 1][0]
      @next_domain_source = domains[domains.index([@domain, @source]) + 1][1]
    else
      @next_domain = ''
      @next_domain_source = ''
      flash[:alert] = 'No more sites'
    end

    begin
      response = open(to_url(@domain), :allow_redirections => :all, :open_timeout => 7)
      @output = 'doc'
      @doc = Nokogiri::HTML(response).to_html
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, OpenSSL::SSL::SSLError, SocketError, OpenURI::HTTPError
      begin
        @output = 'picture'
        Gastly.capture(to_url(@domain), Rails.root.join('public','site_screenshot.png'), timeout: 7000)
      rescue
        @output = 'error'
        @output_error = "<div style='text-align: center;'>Can't load the website <a href='#{to_url(@domain)}' target='_blank'>#{@domain}</a></div>"
      end
    end

  end

  def filter_source
    current = CurrentState.first

    current.domain = nil
    current.domain_source = nil
    current.filter_source = params[:filter_source]
    current.filter_type = params[:filter_type]
    current.save

    redirect_to root_path
  end

  def tagging
    current = CurrentState.first

    unless params[:skip]
      set_bq_vars
      row = {
        @source_header => params[:source],
        @domain_header => params[:domain],
        @table.headers[2] => params[:segment],
        @table.headers[3] => params[:content_type],
        @table.headers[4] => params[:rank],
        @table.headers[5] => DateTime.now,
        @table.headers[6] => params[:location]
      }

      @bigquery.query "DELETE FROM #{@table.query_id} WHERE #{@source_header} = '#{current.domain_source}' AND #{@domain_header} = '#{current.domain}'"
      @table.insert row
    end

    current.update_attributes(
        domain: params[:next_domain], 
        domain_source: params[:next_domain_source])

    redirect_to root_path
  end

  private

    def set_bq_vars
      @bigquery = Google::Cloud::Bigquery.new

      if ENV['manual_dataset'] && ENV['manual_dataset'].length > 0
        @dataset = @bigquery.dataset ENV['manual_dataset']
      end

      @dataset ||= @bigquery.datasets.first

      return unless @dataset

      if ENV['manual_table'] && ENV['manual_table'].length > 0
        @table = @dataset.table ENV['manual_table']
      end

      @table ||= @dataset.tables.first

      return unless @table

      @source_header = @table.headers.first
      @domain_header = @table.headers.second
    end
end
