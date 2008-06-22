#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'json'

require 'yaml'
require 'cgi'
require 'net/http'
require 'uri'

helpers do
  
  def load_credentials(repo_url)
    options = File.open('credentials.yaml','r') { |f| YAML::load(f) }
    return options[repo_url]
  end

  def verify_secret(secret)
    if secret and params[:secret] != secret
      throw :halt, [401, 'Access Denied']
    end
  end
  
end

post '/' do
  push = JSON.parse(params[:payload])
  credentials = load_credentials(push['repository']['url'])

  verify_secret(credentials['secret'])
  
  # Push each changeset to Lighthouse separately so that we can use
  # different API tokens if commits were made by different users.
  push['commits'].each do |commit, details|
    
    commit_author       = details['author']['name']
    commit_author_email = details['author']['email']
    commit_message      = [details['message'], details['url']].join("\n\n")
    commit_time         = details['timestamp']

    commit_changes = (details['added'].collect { |a| ['A', a] } + 
      details['removed'].collect { |r| ['D', r] } + 
      details['modified'].collect { |m| ['U', m] }).to_yaml
    
    changeset_xml = <<-END_XML
<changeset>
  <title>#{CGI.escapeHTML("Changeset [#{commit}] by #{commit_author}")}</title>
  <body>#{CGI.escapeHTML(commit_message)}</body>
  <changes>#{CGI.escapeHTML(commit_changes)}</changes>
  <revision>#{CGI.escapeHTML(commit)}</revision>
  <changed-at type="datetime">#{CGI.escapeHTML(commit_time)}</changed-at>
</changeset>
END_XML
    
    token = credentials['users'] && credentials['users'][commit_author_email] || credentials['default_token']
    raise "No token found." unless token

    url = URI.parse('%s/projects/%d/changesets.xml' % [credentials['account'], credentials['project']])
    
    req = Net::HTTP::Post.new(url.path)
    req.basic_auth token, 'x' # to ensure authentication
    req.body = changeset_xml.strip
    req.set_content_type('application/xml')
    
    res = Net::HTTP.new(url.host, url.port).start { |http| http.request(req) }
    case res
    when Net::HTTPSuccess, Net::HTTPRedirection
      # success!
    else
      raise 'something went wrong!'
    end

  end

  "Changeset(s) accepted."
end  

error do
  'Sorry there was a nasty error - ' + request.env['sinatra.error'].name
end
