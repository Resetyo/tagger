class HomeController < ApplicationController
  include HomeHelper
  http_basic_authenticate_with name: ENV['http_username'],
                               password: ENV['http_password'],
                               only: :index

  def index
    @segments = ['Sports', 'Gaming ', 'Outdoor', 'Fitness', 'Comedy', 'Special Interest', 'Faith', 'News & Politics', 'Personality', 'Lifestyle', 'Kids & Family', 'Music', 'TV & Film', 'Education', 'Subscription Commerce', 'Corporate', 'Events', 'Agency', 'Other']
    @content_types = ['Episodic', 'Long form', 'Short form', 'Broadcast (linear)', 'Live streaming (event based)', 'Audio (podcast)']

    unless set_bq_vars
      @sources = []
      flash[:alert] = "Can't find any table in dataset" if ENV['manual_table'].blank?
      flash[:alert] = "Can't find dataset" if ENV['manual_dataset'].blank?
      return
    end

    @output_error = ''

    sql = "SELECT DISTINCT Source FROM #{@table}"
    @sources = @bigquery.query(sql).map { |s|  s[:Source] }
    session[:sources] = @sources

    current = CurrentState.first_or_create

    filter_type_query = current.filter_type == 'new_domains' ? "Reviewed_Date IS NULL" : "1=1"
    filter_source_query = current.filter_source.present? ? "Source = '#{current.filter_source}'" : "1=1"

    sql = "SELECT COUNT(*) FROM #{@table} WHERE #{filter_type_query} AND #{filter_source_query}"
    total_count = @bigquery.query(sql).first.values.first

    if current.domain.present?
      sql = "WITH Cte AS (SELECT *, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS number FROM #{@table} WHERE #{filter_type_query} AND #{filter_source_query}) SELECT * FROM Cte WHERE Company_Domain = '#{current.domain}'"
      cur_row = @bigquery.query(sql).first

      if cur_row
        cur_row_number = cur_row[:number]
      else
        sql = "SELECT * FROM #{@table} LIMIT 1"
        cur_row = @bigquery.query(sql).first
        cur_row_number = 1
        current.update_attributes(domain: cur_row[:Company_Domain])
      end
    else
      sql = "SELECT * FROM #{@table} WHERE #{filter_type_query} AND #{filter_source_query} LIMIT 1"
      cur_row = @bigquery.query(sql).first
      cur_row_number = 1
      current.update_attributes(domain: cur_row[:Company_Domain])
    end

    @domain = current&.domain
    @source = cur_row[:Source]
    @filter_type = current&.filter_type || :new_domains
    @filter_source = current&.filter_source

    @sites_left = total_count - cur_row_number
    @segment = cur_row[:Segment]
    @content_type = cur_row[:Content_Type]
    @rank = cur_row[:Rank]
    @location = cur_row[:Location]
    @notes = cur_row[:Notes]

    if total_count > cur_row_number
      sql = "WITH Cte AS (select Company_Domain, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS number FROM #{@table} WHERE #{filter_type_query} AND #{filter_source_query}) SELECT * FROM Cte WHERE number = #{cur_row_number + 1}"
      @next_domain = @bigquery.query(sql).first[:Company_Domain]
    else
      @next_domain = ''
      @next_domain_source = ''
      flash[:alert] = 'No more sites'
    end

    return if cur_row[:Company_Domain].blank?

    #open uri
    begin
      logger.info 'open uri'
      response = open(to_url(@domain), {
                    allow_redirections: :all,
                    open_timeout: 5,
                    ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE})
      @output = 'doc'
      @doc = Nokogiri::HTML.parse(response)
      # @doc.encoding = 'utf-8'
      @doc.to_html.gsub(/\.location\.replace\(.+\)/,'')
    rescue => error #Errno::ECONNREFUSED, Net::OpenTimeout, OpenSSL::SSL::SSLError, SocketError, OpenURI::HTTPError
      # begin
      #   logger.info 'make screenshot'
      #   @output = 'picture'
      #   screenshot = Gastly.screenshot(to_url(@domain), timeout: 5000)
      #   screenshot.phantomjs_options = '--ignore-ssl-errors=true'
      #   image = screenshot.capture
      #   image.save(Rails.root.join('public','site_screenshot.png'))
      # rescue
        @output = 'error'
        @output_error = "<div style='text-align: center;'>Can't load the website <a href='#{to_url(@domain)}' target='_blank'>#{@domain}</a><br>#{error.message}</div>"
      # end
    end
  end

  def filter_source
    current = CurrentState.first

    current.domain = nil
    current.filter_source = params[:filter_source].present? ? params[:filter_source] : nil
    current.filter_type = params[:filter_type].present? ? params[:filter_type] : 0
    current.save

    redirect_to root_path
  end

  def tagging
    current = CurrentState.first

    unless params[:skip]
      set_bq_vars
      # row = {
      #   :Source => params[:source],
      #   :Company_Domain => params[:domain],
      #   :Segment => params[:segment],
      #   :Content_Type => params[:content_type],
      #   :Rank => params[:rank],
      #   :Reviewed_Date => DateTime.now,
      #   :Location => params[:location],
      #   :Notes => params[:notes]
      # }

      # @bigquery.query "DELETE FROM #{@table.query_id} WHERE Source = '#{current.domain_source}' AND Company_Domain = '#{current.domain}'"
      # @table.insert row

      row = "Source = '#{params[:source]}', "\
            "Company_Domain = '#{params[:domain]}', "\
            "Segment = '#{params[:segment]}', "\
            "Content_Type = '#{params[:content_type]}', "\
            "Rank = '#{params[:rank]}', "\
            "Reviewed_Date = '#{DateTime.now}', "\
            "Location = '#{params[:location]}', "\
            "Notes = '#{params[:notes].gsub(/\r\n/,'\\r\\n')}'"

      @bigquery.query "UPDATE #{@table} SET #{row} WHERE Company_Domain = '#{current.domain}'"
    end

    current.update_attributes(
        domain: params[:next_domain]
      )

    redirect_to root_path
  end

  def report
    set_bq_vars

    sql = "SELECT Source, COUNT(*) FROM #{@table} GROUP BY Source"
    counts = @bigquery.query(sql)

    sql = "SELECT Source, COUNT(*) FROM #{@table} WHERE Reviewed_Date IS NULL GROUP BY Source"
    new_counts = @bigquery.query(sql)

    @lists = {}

    counts.each do |row|
      @lists[row[:Source]] ||= {}
      @lists[row[:Source]][:targets_count] = row[:f0_]
    end

    new_counts.each do |row|
      @lists[row[:Source]] ||= {}
      @lists[row[:Source]][:new_targets_count] = row[:f0_]
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

    sql = "SELECT Company_Domain FROM #{@table} WHERE Company_Domain IN (#{domains.map{|d|"'#{d}'"}.join(', ')})"
    matched_domains = @bigquery.query(sql).map { |d| d[:Company_Domain] }

    # @table.data.all.each do |row|
    #   duplicate[row[:Company_Domain]] = true if domains.include?(row[:Company_Domain])
    # end

    domains.each do |domain|
      duplicates << domain && next if matched_domains.include?(domain)

      row = {
        :Source => params[:source],
        :Company_Domain => domain
      }

      dataset = @bigquery.dataset ENV['manual_dataset']
      table = dataset.table ENV['manual_table']
      table.insert row
      added << domain
    end

    redirect_to add_domains_path(added: added, duplicates: duplicates)
  end

  private

    def set_bq_vars
      @bigquery = Google::Cloud::Bigquery.new
      @table = "#{ENV['manual_dataset']}.#{ENV['manual_table']}"
    end
end
