# encoding: utf-8

require 'mongoid'
require 'carrierwave'
require 'carrierwave/validations/active_model'

module Mongoid
  module Document    
    def each_embedded association_name, &b
      Array(send(association_name)).each &b
    end
  end
end

CarrierWave::Uploader::Base.class_eval do
  def name; model.send("#{mounted_as}_filename") end
end

CarrierWave::SanitizedFile.class_eval do
  def sanitize_regexp
    /[^[:word:]\.\-\+\s_]/i
  end
end

CarrierWave::Uploader::Cache.class_eval do
  def original_filename=(filename)
    raise CarrierWave::InvalidParameter, "invalid filename" unless filename =~ /\A[[:word:]\.\-\+\s_]+\z/i
    @original_filename = filename
  end
end


module CarrierWave
  module Mongoid
    include CarrierWave::Mount
    ##
    # See +CarrierWave::Mount#mount_uploader+ for documentation
    #
    def mount_uploader(column, uploader=nil, options={}, &block)
      field options[:mount_on] || column

      super

      alias_method :read_uploader, :read_attribute
      alias_method :write_uploader, :write_attribute
      public :read_uploader
      public :write_uploader

      include CarrierWave::Validations::ActiveModel

      validates_integrity_of  column if uploader_option(column.to_sym, :validate_integrity)
      validates_processing_of column if uploader_option(column.to_sym, :validate_processing)

      after_save :"store_#{column}!"
      before_save :"write_#{column}_identifier"
      after_destroy :"remove_#{column}!"
      before_update :"store_previous_model_for_#{column}"
      after_save :"remove_previously_stored_#{column}"

      class_eval <<-RUBY, __FILE__, __LINE__+1
        def #{column}=(new_file)
          column = _mounter(:#{column}).serialization_column
          send(:"\#{column}_will_change!")
          super
        end

        def find_previous_model_for_#{column}
          if self.embedded?
            ancestors       = [[ self.metadata.key, self._parent ]].tap { |x| x.unshift([ x.first.last.metadata.key, x.first.last._parent ]) while x.first.last.embedded? }
            first_parent = ancestors.first.last
            reloaded_parent = first_parent.class.find(first_parent.to_key.first)
            ancestors.inject(reloaded_parent) { |parent,(key,ancestor)| (parent.is_a?(Array) ? parent.find(ancestor.to_key.first) : parent).send(key) }.find(to_key.first)
          else
            self.class.find(to_key.first)
          end
        end
      RUBY
    end
    
    def mount_embedded_uploader association_name, column
      after_save do |doc|
        doc.each_embedded(association_name) do |embedded|
          embedded.send "store_#{column}!"
        end
      end
    
      before_save do |doc|
        doc.each_embedded(association_name) do |embedded|
          embedded.send "write_#{column}_identifier"
        end
      end
    
      after_destroy do |doc|
        doc.each_embedded(association_name) do |embedded|
          embedded.send "remove_#{column}!"
        end
      end
    end
  end # Mongoid
end # CarrierWave

Mongoid::Document::ClassMethods.send(:include, CarrierWave::Mongoid)
