class HomeController < ApplicationController
  include HomeHelper
  http_basic_authenticate_with name: ENV['http_username'], password: ENV['http_password'], only: :index

  def index
    @segments = ['Sports', 'Gaming ', 'Outdoor', 'Fitness', 'Comedy', 'Special Interest', 'Faith', 'News & Politics', 'Personality', 'Lifestyle', 'Kids & Family', 'Music', 'TV & Film', 'Education', 'Subscription Commerce', 'Corporate', 'Events', 'Agency', 'Other']
    @content_types = ['Episodic', 'Long form', 'Short form', 'Broadcast (linear)', 'Live streaming (event based)', 'Audio (podcast)']

    unless set_bq_vars
      @sources = []
      flash[:alert] = "Can't find any table in dataset" unless @table
      flash[:alert] = "Can't find dataset" unless @dataset
      return
    end

    @sources = []
    @output_error = ''

    current = CurrentState.first_or_create(
                domain: @table.data[0][@domain_header],
                domain_source: @table.data[0][@source_header]
              )

    domains = []
    domains_data = []

    @table.data.all.each do |row|
      @sources << row[@source_header]

      next if current.filter_type == 'new_domains' && row[:Reviewed_Date].present?
      next if current.filter_source.present? && current.filter_source != row[@source_header]

      domains << [
        row[@domain_header],
        row[@source_header]
      ]

      domains_data << [
        row[:Segment],
        row[:Content_Type],
        row[:Rank],
        row[:Location],
        row[:Notes]
      ]
    end

    @sources.uniq!
    session[:sources] = @sources

    if current.domain.blank? || current.domain_source.blank?
      current.update_attributes(
        domain: domains[0][0], 
        domain_source: domains[0][1]
      )
    end

    @domain = current&.domain
    @source = current&.domain_source
    @filter_type = current&.filter_type || :new_domains
    @filter_source = current&.filter_source
    @sites_left = domains.count - domains.index([@domain, @source]) - 1
    @segment = domains_data[domains.index([@domain, @source])][0]
    @content_type = domains_data[domains.index([@domain, @source])][1]
    @rank = domains_data[domains.index([@domain, @source])][2]
    @location = domains_data[domains.index([@domain, @source])][3]
    @notes = domains_data[domains.index([@domain, @source])][4]

    if domains.count > domains.index([@domain, @source]) + 1
      @next_domain = domains[domains.index([@domain, @source]) + 1][0]
      @next_domain_source = domains[domains.index([@domain, @source]) + 1][1]
    else
      @next_domain = ''
      @next_domain_source = ''
      flash[:alert] = 'No more sites'
    end

    return if @table.data[0][@domain_header].blank?

    begin
      logger.info 'open uri'
      response = open(to_url(@domain), {
                    allow_redirections: :all,
                    open_timeout: 5,
                    ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE})
      @output = 'doc'
      @doc = Nokogiri::HTML(response).to_html
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, OpenSSL::SSL::SSLError, SocketError, OpenURI::HTTPError
      begin
        logger.info 'make screenshot'
        @output = 'picture'
        screenshot = Gastly.screenshot(to_url(@domain), timeout: 5000)
        screenshot.phantomjs_options = '--ignore-ssl-errors=true'
        image = screenshot.capture
        image.save(Rails.root.join('public','site_screenshot.png'))
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
      # row = {
      #   @source_header => params[:source],
      #   @domain_header => params[:domain],
      #   :Segment => params[:segment],
      #   :Content_Type => params[:content_type],
      #   :Rank => params[:rank],
      #   :Reviewed_Date => DateTime.now,
      #   :Location => params[:location],
      #   :Notes => params[:notes]
      # }

      # @bigquery.query "DELETE FROM #{@table.query_id} WHERE #{@source_header} = '#{current.domain_source}' AND #{@domain_header} = '#{current.domain}'"
      # @table.insert row

      row = "#{@source_header.to_s} = '#{params[:source]}', "\
            "#{@domain_header.to_s} = '#{params[:domain]}', "\
            "Segment = '#{params[:segment]}', "\
            "Content_Type = '#{params[:content_type]}', "\
            "Rank = '#{params[:rank]}', "\
            "Reviewed_Date = '#{DateTime.now}', "\
            "Location = '#{params[:location]}', "\
            "Notes = '#{params[:notes].gsub(/\r\n/,'\\r\\n')}'"

      @bigquery.query "UPDATE #{@table.query_id} SET #{row} WHERE #{@source_header} = '#{current.domain_source}' AND #{@domain_header} = '#{current.domain}'"
    end

    current.update_attributes(
        domain: params[:next_domain], 
        domain_source: params[:next_domain_source]
      )

    redirect_to root_path
  end

  def report
    set_bq_vars

    @lists = {}

    @table.data.all.each do |row|
      if @lists[row[@source_header]].blank?
        @lists[row[@source_header]] = { targets_count: 0, new_targets_count: 0 }
      end

      @lists[row[@source_header]][:targets_count] += 1

      if row[:Reviewed_Date].blank?
        @lists[row[@source_header]][:new_targets_count] += 1
      end
    end
  end

  def add_domains
    @sources = session[:sources] || []

    @added = params[:added] || []
    @duplicates = params[:duplicates] || []
  end

  def add_domains_form
    set_bq_vars

    domains = params[:domains].split(/\r\n|\r|\n/)
    duplicate = {}
    added = []
    duplicates = []

    @table.data.all.each do |row|
      duplicate[row[@domain_header]] = true if domains.include?(row[@domain_header])
    end

    domains.each do |domain|
      duplicates << domain && next if duplicate[domain]

      row = {
        @source_header => params[:source],
        @domain_header => domain
      }

      @table.insert row
      added << domain
    end

    redirect_to add_domains_path(added: added, duplicates: duplicates)
  end

  private

    def set_bq_vars
      @bigquery = Google::Cloud::Bigquery.new

      if ENV['manual_dataset'] && ENV['manual_dataset'].length > 0
        @dataset = @bigquery.dataset ENV['manual_dataset']
      end

      @dataset ||= @bigquery.datasets.first

      return unless @dataset

      return unless ENV['manual_table'] && ENV['manual_table'].length > 0

      @table = @dataset.table ENV['manual_table']

      return unless @table

      @source_header = :Source
      @domain_header = :Company_Domain
    end
end
