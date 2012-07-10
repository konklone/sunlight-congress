#!/usr/bin/env ruby

require './config/environment'

require './analytics/api_key'
require './analytics/hits'

set :logging, false

configure(:development) do |config|
  require 'sinatra/reloader'
  config.also_reload "./config/environment.rb"
  config.also_reload "./analytics/*.rb"
  config.also_reload "./models/*.rb"
  config.also_reload "./queryable.rb"
  config.also_reload "./searchable.rb"
end


get queryable_route do
  model = params[:captures][0].singularize.camelize.constantize
  format = params[:captures][1]

  fields = Queryable.fields_for model, params
  conditions = Queryable.conditions_for model, params
  order = Queryable.order_for model, params
  pagination = Queryable.pagination_for params
  
  if params[:explain] == 'true'
    results = Queryable.explain_for model, conditions, fields, order, pagination
  else
    results = Queryable.results_for model, conditions, fields, order, pagination
  end
  
  if format == 'json'
    json results
  elsif format == 'xml'
    xml results
  end
end


get searchable_route do
  model = params[:captures][0].singularize.camelize.constantize
  format = params[:captures][1]
  
  error 400, "You must provide a search term with the 'query' parameter (for phrase searches) or 'q' parameter (for query string searches)." unless params[:query] or params[:q]

  term = Searchable.term_for params
  fields = Searchable.fields_for model, params
  search_fields = Searchable.search_fields_for model, params

  if search_fields.empty?
    error 400, "You must search one of the following fields for #{params[:captures][0]}: #{model.searchable_fields.join(", ")}"
  end
  
  if params[:query]
    query = Searchable.query_for term, model, params, search_fields
  elsif params[:q]
    query = Searchable.relaxed_query_for term, model, params, search_fields
  end

  filter = Searchable.filter_for model, params
  order = Searchable.order_for model, params
  pagination = Searchable.pagination_for model, params
  other = Searchable.other_options_for model, params, search_fields
  
  
  if params[:explain] == 'true'
    results = Searchable.explain_for term, model, query, filter, fields, order, pagination, other
  else
    results = Searchable.results_for term, model, query, filter, fields, order, pagination, other
  end
  
  if format == 'json'
    json results
  elsif format == 'xml'
    xml results
  end
end


helpers do

  def error(status, message)
    format = params[:captures][1]

    results = {
      error: message,
      status: status
    }

    if format == "json"
      halt 200, json(results)
    else
      halt 200, xml(results)
    end
  end
  
  def json(results)
    response['Content-Type'] = 'application/json'
    json = Oj.dump results, mode: :compat, time_format: :ruby
    params[:callback].present? ? "#{params[:callback]}(#{json});" : json
  end
  
  def xml(results)
    xml_exceptions results
    response['Content-Type'] = 'application/xml'
    results.to_xml :root => 'results', :dasherize => false
  end
  
  # a hard-coded XML exception for vote names, which I foolishly made as keys
  # this will be fixed in v2
  def xml_exceptions(results)
    if results['votes']
      results['votes'].each do |vote|
        if vote['vote_breakdown']
          vote['vote_breakdown'] = dasherize_hash vote['vote_breakdown']
        end
      end
    end
  end
  
  def dasherize_hash(original)
    hash = original.dup
    
    hash.keys.each do |key|
      value = hash.delete key
      key = key.tr(' ', '-')
      if value.is_a?(Hash)
        hash[key] = dasherize_hash(value)
      else
        hash[key] = value
      end
    end
    
    hash
  end
  
end