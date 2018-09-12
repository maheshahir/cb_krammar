# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

class SearchController < ApplicationController
  prepend_before_action :authentication_check

  # GET|POST /api/v1/search
  # GET|POST /api/v1/search/:objects

  def search_generic

    # enable search only for users with valid session
    if !current_user
      response_access_deny
      return true
    end

    # get params
    query = params[:query]
    if query.respond_to?(:permit!)
      query = query.permit!.to_h
    end
    limit = params[:limit] || 10

    # convert objects string into array of class names
    # e.g. user-ticket-another_object = %w( User Ticket AnotherObject )
    objects = if !params[:objects]
                Setting.get('models_searchable')
              else
                params[:objects].split('-').map(&:camelize)
              end

    # get priorities of result
    objects_in_order = []
    objects_in_order_hash = {}
    objects.each do |object|
      local_class = object.constantize
      preferences = local_class.search_preferences(current_user)
      next if !preferences
      objects_in_order_hash[preferences[:prio]] = local_class
    end
    objects_in_order_hash.keys.sort.reverse_each do |prio|
      objects_in_order.push objects_in_order_hash[prio]
    end

    # try search index backend
    assets = {}
    result = []
    if SearchIndexBackend.enabled?

      # get direct search index based objects
      objects_with_direct_search_index = []
      objects_without_direct_search_index = []
      objects.each do |object|
        preferences = object.constantize.search_preferences(current_user)
        next if !preferences
        if preferences[:direct_search_index]
          objects_with_direct_search_index.push object
        else
          objects_without_direct_search_index.push object
        end
      end

      # do only one query to index search backend
      if objects_with_direct_search_index.present?
        items = SearchIndexBackend.search(query, limit, objects_with_direct_search_index)
        items.each do |item|
          require item[:type].to_filename
          local_class = Kernel.const_get(item[:type])
          record = local_class.lookup(id: item[:id])
          next if !record
          assets = record.assets(assets)
          item[:type] = local_class.to_app_model.to_s
          result.push item
        end
      end

      # e. g. do ticket query by Ticket class to handle ticket permissions
      objects_without_direct_search_index.each do |object|
        object_result = search_generic_backend(object.constantize, query, limit, current_user, assets)
        if object_result.present?
          result = result.concat(object_result)
        end
      end

      # sort order by object priority
      result_in_order = []
      objects_in_order.each do |object|
        result.each do |item|
          next if item[:type] != object.to_app_model.to_s
          item[:id] = item[:id].to_i
          result_in_order.push item
        end
      end
      result = result_in_order

    else

      # do query
      objects_in_order.each do |object|
        object_result = search_generic_backend(object, query, limit, current_user, assets)
        if object_result.present?
          result = result.concat(object_result)
        end
      end
    end

    render json: {
      assets: assets,
      result: result,
    }
  end

  private

  def search_generic_backend(object, query, limit, current_user, assets)
    found_objects = object.search(
      query:        query,
      limit:        limit,
      current_user: current_user,
    )
    result = []
    found_objects.each do |found_object|
      item = {
        id:   found_object.id,
        type: found_object.class.to_app_model.to_s
      }
      result.push item
      assets = found_object.assets(assets)
    end
    result
  end
end
