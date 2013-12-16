require 'addressable/uri'
require 'twitter/arguments'
require 'twitter/cursor'
require 'twitter/user'

module Twitter
  module REST
    module API
      module Utils
        DEFAULT_CURSOR = -1
        URI_SUBSTRING = '://'

        class << self
          def included(base)
            base.extend(ClassMethods)
          end
        end

        module ClassMethods
          def deprecate_alias(new_name, old_name)
            define_method(new_name) do |*args, &block|
              warn "#{Kernel.caller.first}: [DEPRECATION] ##{new_name} is deprecated. Use ##{old_name} instead."
              send(old_name, *args, &block)
            end
          end
        end

      private

        # Take a URI string or Twitter::Identity object and return its ID
        #
        # @param object [Integer, String, URI, Twitter::Identity] An ID, URI, or object.
        # @return [Integer]
        def extract_id(object)
          case object
          when ::Integer
            object
          when ::String
            object.split('/').last.to_i
          when URI
            object.path.split('/').last.to_i
          when Twitter::Identity
            object.id
          end
        end

        # @param request_method [Symbol]
        # @param path [String]
        # @param args [Array]
        # @return [Array<Twitter::User>]
        def threaded_user_objects_from_response(request_method, path, args)
          arguments = Twitter::Arguments.new(args)
          arguments.flatten.threaded_map do |user|
            object_from_response(Twitter::User, request_method, path, merge_user(arguments.options, user))
          end
        end

        # @param request_method [Symbol]
        # @param path [String]
        # @param args [Array]
        # @return [Array<Twitter::User>]
        def user_objects_from_response(request_method, path, args)
          arguments = Twitter::Arguments.new(args)
          merge_user!(arguments.options, arguments.pop || screen_name) unless arguments.options[:user_id] || arguments.options[:screen_name]
          objects_from_response(Twitter::User, request_method, path, arguments.options)
        end

        # @param klass [Class]
        # @param request_method [Symbol]
        # @param path [String]
        # @param args [Array]
        # @return [Array]
        def objects_from_response_with_user(klass, request_method, path, args) # rubocop:disable ParameterLists
          arguments = Twitter::Arguments.new(args)
          merge_user!(arguments.options, arguments.pop)
          objects_from_response(klass, request_method, path, arguments.options)
        end

        # @param klass [Class]
        # @param request_method [Symbol]
        # @param path [String]
        # @param options [Hash]
        # @return [Array]
        def objects_from_response(klass, request_method, path, options = {}) # rubocop:disable ParameterLists
          response = send(request_method.to_sym, path, options)[:body]
          objects_from_array(klass, response)
        end

        # @param klass [Class]
        # @param array [Array]
        # @return [Array]
        def objects_from_array(klass, array)
          array.map do |element|
            klass.new(element)
          end
        end

        # @param klass [Class]
        # @param request_method [Symbol]
        # @param path [String]
        # @param args [Array]
        # @return [Array]
        def threaded_objects_from_response(klass, request_method, path, args) # rubocop:disable ParameterLists
          arguments = Twitter::Arguments.new(args)
          arguments.flatten.threaded_map do |object|
            id = extract_id(object)
            object_from_response(klass, request_method, path, arguments.options.merge(:id => id))
          end
        end

        # @param klass [Class]
        # @param request_method [Symbol]
        # @param path [String]
        # @param options [Hash]
        # @return [Object]
        def object_from_response(klass, request_method, path, options = {}) # rubocop:disable ParameterLists
          response = send(request_method.to_sym, path, options)
          klass.from_response(response)
        end

        # @param collection_name [Symbol]
        # @param klass [Class]
        # @param request_method [Symbol]
        # @param path [String]
        # @param args [Array]
        # @return [Twitter::Cursor]
        def cursor_from_response_with_user(collection_name, klass, request_method, path, args) # rubocop:disable ParameterLists
          arguments = Twitter::Arguments.new(args)
          merge_user!(arguments.options, arguments.pop || screen_name) unless arguments.options[:user_id] || arguments.options[:screen_name]
          cursor_from_response(collection_name, klass, request_method, path, arguments.options)
        end

        # @param collection_name [Symbol]
        # @param klass [Class]
        # @param request_method [Symbol]
        # @param path [String]
        # @param options [Hash]
        # @return [Twitter::Cursor]
        def cursor_from_response(collection_name, klass, request_method, path, options) # rubocop:disable ParameterLists
          merge_default_cursor!(options)
          response = send(request_method.to_sym, path, options)
          Twitter::Cursor.from_response(response, collection_name.to_sym, klass, self, request_method, path, options)
        end

        def handle_forbidden_error(klass, error)
          error = error.message == klass::MESSAGE ? klass.new : error
          fail error
        end

        def merge_default_cursor!(options)
          options[:cursor] = DEFAULT_CURSOR unless options[:cursor]
        end

        def screen_name
          @screen_name ||= verify_credentials.screen_name
        end

        # Take a user and merge it into the hash with the correct key
        #
        # @param hash [Hash]
        # @param user [Integer, String, Twitter::User] A Twitter user ID, screen name, URI, or object.
        # @return [Hash]
        def merge_user(hash, user, prefix = nil)
          merge_user!(hash.dup, user, prefix)
        end

        # Take a user and merge it into the hash with the correct key
        #
        # @param hash [Hash]
        # @param user [Integer, String, URI, Twitter::User] A Twitter user ID, screen name, URI, or object.
        # @return [Hash]
        def merge_user!(hash, user, prefix = nil)
          case user
          when Integer
            set_compound_key('user_id', user, hash, prefix)
          when String
            if user[URI_SUBSTRING]
              set_compound_key('screen_name', user.split('/').last, hash, prefix)
            else
              set_compound_key('screen_name', user, hash, prefix)
            end
          when URI, Addressable::URI
            set_compound_key('screen_name', user.path.split('/').last, hash, prefix)
          when Twitter::User
            set_compound_key('user_id', user.id, hash, prefix)
          end
        end

        def set_compound_key(key, value, hash, prefix = nil) # rubocop:disable ParameterLists
          compound_key = [prefix, key].compact.join('_').to_sym
          hash[compound_key] = value
          hash
        end

        # Take a multiple users and merge them into the hash with the correct keys
        #
        # @param hash [Hash]
        # @param users [Enumerable<Integer, String, Twitter::User>] A collection of Twitter user IDs, screen_names, or objects.
        # @return [Hash]
        def merge_users(hash, users)
          merge_users!(hash.dup, users)
        end

        # Take a multiple users and merge them into the hash with the correct keys
        #
        # @param hash [Hash]
        # @param users [Enumerable<Integer, String, URI, Twitter::User>] A collection of Twitter user IDs, screen_names, URIs, or objects.
        # @return [Hash]
        def merge_users!(hash, users)
          user_ids, screen_names = collect_user_ids_and_screen_names(users)
          hash[:user_id] = user_ids.join(',') unless user_ids.empty?
          hash[:screen_name] = screen_names.join(',') unless screen_names.empty?
          hash
        end

        def collect_user_ids_and_screen_names(users) # rubocop:disable MethodLength
          user_ids, screen_names = [], []
          users.flatten.each do |user|
            case user
            when Integer
              user_ids << user
            when String
              if user[URI_SUBSTRING]
                screen_names << user.split('/').last
              else
                screen_names << user
              end
            when URI
              screen_names << user.path.split('/').last
            when Twitter::User
              user_ids << user.id
            end
          end
          [user_ids, screen_names]
        end
      end
    end
  end
end
