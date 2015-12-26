require 'rubygems'
require 'bundler'
Bundler.require

require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/date/calculations'

# hack to make Figaro work with Sinatra:
# based on https://github.com/laserlemon/figaro/issues/60
# override the path and environment methods of Figaro::Application,
#  then load Figaro as part of Sinatra app config block

module Figaro
  class Application
    def path
      @path ||= File.join(Resty.settings.root, "config", "application.yml")
    end

    def environment
      Resty.settings.environment
    end
  end
end


class Resty < Sinatra::Base

  configure do
    Figaro.load
  end

  def html
    haml <<EOstring
!!!
%head
%body
  %h1 #{yield}

EOstring
  end

  get '/test' do
    html { "App OK - Dyno #{ENV['DYNO']}" }
  end

  get '/hilites' do
    amazon_user = Figaro.env.amazon_user
    amazon_pass = Figaro.env.amazon_pass
    session = Mechanize.new do |agent|
      agent.user_agent_alias = 'Mac Safari'
      agent.follow_meta_refresh = true
      agent.redirect_ok = true
    end
    home = session.get('https://kindle.amazon.com/login').form_with(:name => 'signIn') do |f|
      f.email = amazon_user
      f.password = amazon_pass
      f.radiobutton_with(:id => 'ap_signin_existing_radio').check
    end.submit
    page = home.link_with(:href => '/your_reading').click
    books = []
    next_page = 2
    while page
      page.parser.css('td.titleAndAuthor a').each do |link|
        books += [link.text, link['href'].gsub(Regexp.new('^(.*)/'), '')]
      end
      if (false && link = page.link_with(:text => next_page.to_s))
        page = link.click
        next_page += 1
      else
        page = nil
      end
    end
    str = ''
    # this link appears to be the magic formula, once a valid session is
    # established
    books.each_slice(2) do |title, asin|
      str << %Q{<p><a href="https://kindle.amazon.com/your_highlights?current_offset=1&upcoming_asins[]=#{asin}">#{title}</a></p>\n}
    end
    # set amazon cookie by trying to follow one link
    next_login_page = s.get("https://kindle.amazon.com/your_highlights?current_offset=1&upcoming_asins[]=#{books[1]}")
    next_login_page.form_with(:id => 'ap_signin_form') do |f|
      f.ap_email = amazon_user
      f.ap_password = pass
    end.submit                  # this should set the cookie
    html { str }
  end
  
  get '/booksales' do
    require 'json'
    # createspace
    cs_user = Figaro.env.createspace_user
    cs_pass = Figaro.env.createspace_pass
    session = Mechanize.new
    main_page =
      session.post('https://www.createspace.com/LoginProc.do',
      'action' => 'Log In', 'login' => cs_user, 'password' => cs_pass)
    cs_num_units =
      main_page.
      parser.
      xpath("//td[@class='table_col_left sales_col']").
      text.to_i
    # amazon kdp
    session = Mechanize.new
    session.user_agent_alias = 'Mac Safari'
    session.get 'https://www.amazon.com/ap/signin?openid.assoc_handle=amzn_dtp&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.return_to=https%3A%2F%2Fkdp.amazon.com%2Fself-publishing%2Fsignin%2Freturn&marketPlaceId=ATVPDKIKX0DER&pageId=amzn_dtp&openid.mode=checkid_setup&openid.pape.max_auth_age=0&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0'
    form = session.get('https://www.amazon.com/ap/signin?openid.assoc_handle=amzn_dtp&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.return_to=https%3A%2F%2Fkdp.amazon.com%2Fself-publishing%2Fsignin%2Freturn&marketPlaceId=ATVPDKIKX0DER&pageId=amzn_dtp&openid.mode=checkid_setup&openid.pape.max_auth_age=0&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0').
      form_with(:name => 'signIn')
    params = {'email' => cs_user,  'password' => cs_pass}
    %w(appActionToken appAction openid.pape.max_auth_age openid.ns openid.ns.pape pageId openid.identity openid.claimed_id openid.mode openid.assoc_handle openid.return_to).each do |field|
      params[field] = form[field]
    end
    session.post('https://www.amazon.com/ap/signin', params)
    response = session.get('https://kdp.amazon.com/self-publishing/reports/transactionReport?_=1326589411161&previousMonthReports=false&marketplaceID=ATVPDKIKX0DER')
    hash = JSON.parse(response.body)
    kindle_units = hash['aaData'][0][5]
    start_date,end_date = hash['start-date'][0,5], hash['end-date'][0,5]
    kindle_royalty = sprintf("%.2f", 9.99 * 0.70 * kindle_units.to_i)
    print_royalty = sprintf("%.2f", 12.53 * cs_num_units.to_i)
    html { "#{kindle_units} ebooks (#{start_date}-#{end_date}) (#{kindle_royalty}), #{cs_num_units} print books (#{print_royalty})" }
  end

  get '/wageworks' do
    username = Figaro.env.wageworks_user
    password = Figaro.env.wageworks_pass
    puts "#{username} #{password}"
    url = 'https://participant.wageworks.com/'
    session = Mechanize.new
    session.user_agent_alias = 'Mac Safari'
    token = session.get(url).parser.xpath("//input[@name='__VIEWSTATE']")[0]['value']
    commuter_card_amount =
      session.post('https://participant.wageworks.com/Account/LoginProcess.aspx',
      'txtUserName' => username,
      'txtPassword' => password,
      'hidPageMode' => 'Login',
      '__VIEWSTATE' => token).
      search('span#bodySection_ctl01_transitCardBalanceLabel').
      text
    html { commuter_card_amount }
  end

  get '/clipper' do
    url = 'https://clippercard.com/ClipperWeb/login.do'
    username = Figaro.env.clipper_user
    password = Figaro.env.clipper_pass
    agent = Mechanize.new
    login_form = agent.get('https://clippercard.com/').form_with(:name => 'LoginForm')
    login_form.username = username
    login_form.password = password
    amount =
      agent.submit(login_form).
      link_with(:href => /cardValue/i).
      click.
      parser.xpath("//tr/td[contains(.,'Clipper Cash')]").first.
      next_sibling.next_sibling.
      content.match(/\$(\d+\.\d+)/)
    html { $1 }
  end

  get '/transerve' do
    user = Figaro.env.transerve_user
    pass = Figaro.env.transerve_pass
    security_answers = {
      Figaro.env.transerve_q1 => Figaro.env.transerve_a1,
      Figaro.env.transerve_q2 => Figaro.env.transerve_a2,
      Figaro.env.transerve_q3 => Figaro.env.transerve_a3
    }
    agent = Mechanize.new
    url = 'https://www.ucard.chase.com/'
    until url.nil?
      main = agent.get url
      url = if ((r = main.meta_refresh) && !r.empty?) then URI.join(url, r.first.uri) else nil end
    end
    login_form = main.form_with(:name => 'form1')
    login_form.userId = user
    login_form.password = pass
    result = agent.submit(login_form)
    # if it forces us to validate security question, do so
    if (security_question_form =
        result.form_with(:action => '/authenticate_isSecurityAnswerValid.action'))
      question =
        result.parser.xpath('//td[@class="cdpLeftAlignedTdLabel"]').first.text.strip
      security_question_form.securityAnswer = security_answers[question]
      result = agent.submit(security_question_form)
    end
    # ok, now we should be on main login page
    today = Date.today
    # when will balance expire? on 10th of each month.
    exp_date = if today.day < 10
               then today.change(:day => 10)
               else (today.next_month).change(:day => 10)
               end
    days_left = (exp_date - today).to_i
    message = " will be forfeited on #{exp_date.strftime('%b %e')} (in #{days_left} days)"
    html { (result.body =~ /\$\s*(\d+\.\d\d)/ ?  $1 : '???') + message }
  end

end
