# frozen_string_literal: true

module SitePrism
  module ElementContainer
    attr_reader :mapped_items, :expected_items

    def element(element_name, *find_args)
      build(element_name, *find_args) do
        define_method(element_name.to_s) do |*runtime_args, &element_block|
          self.class.raise_if_block(self, element_name.to_s, !element_block.nil?)
          find_first(*self.class.merge_args(find_args, runtime_args))
        end
      end
    end

    def elements(collection_name, *find_args)
      build(collection_name, *find_args) do
        define_method(collection_name.to_s) do |*runtime_args, &element_block|
          self.class.raise_if_block(self, collection_name.to_s, !element_block.nil?)
          find_all(*self.class.merge_args(find_args, runtime_args))
        end
      end
    end
    alias collection elements

    def expected_elements(*elements)
      @expected_items = elements
    end

    def section(section_name, *args, &block)
      section_class, find_args = extract_section_options(args, &block)
      build(section_name, *find_args) do
        define_method section_name do |*runtime_args, &runtime_block|
          section_class.new self, find_first(*self.class.merge_args(find_args, runtime_args)), &runtime_block
        end
      end
    end

    def sections(section_collection_name, *args, &block)
      section_class, find_args = extract_section_options(args, &block)
      build(section_collection_name, *find_args) do
        define_method(section_collection_name) do |*runtime_args, &element_block|
          self.class.raise_if_block(self, section_collection_name.to_s, !element_block.nil?)
          find_all(*self.class.merge_args(find_args, runtime_args)).map do |element|
            section_class.new(self, element)
          end
        end
      end
    end

    def iframe(iframe_name, iframe_page_class, *args)
      element_find_args = deduce_iframe_element_find_args(args)
      scope_find_args = deduce_iframe_scope_find_args(args)
      add_to_mapped_items(iframe_name)
      add_iframe_helper_methods(iframe_name, *element_find_args)
      define_method(iframe_name) do |&block|
        within_frame(*scope_find_args) do
          block.call iframe_page_class.new
        end
      end
    end

    def add_to_mapped_items(item)
      @mapped_items ||= []
      @mapped_items << item
    end

    def raise_if_block(obj, name, has_block)
      return unless has_block

      raise SitePrism::UnsupportedBlock, "#{obj.class}##{name}"
    end

    def merge_args(find_args, runtime_args, override_options = {})
      find_args = find_args.dup
      runtime_args = runtime_args.dup
      options = {}
      options.merge!(find_args.pop) if find_args.last.is_a? Hash
      options.merge!(runtime_args.pop) if runtime_args.last.is_a? Hash
      options.merge!(override_options)
      [*find_args, *runtime_args, options]
    end

    private

    def build(name, *find_args)
      if find_args.empty?
        create_no_selector(name)
      else
        add_to_mapped_items(name)
        yield
      end
      add_helper_methods(name, *find_args)
    end

    def add_helper_methods(name, *find_args)
      create_existence_checker(name, *find_args)
      create_nonexistence_checker(name, *find_args)
      create_waiter(name, *find_args)
      create_nonexistence_waiter(name, *find_args)
      create_visibility_waiter(name, *find_args)
      create_invisibility_waiter(name, *find_args)
    end

    def add_iframe_helper_methods(name, *find_args)
      create_existence_checker(name, *find_args)
      create_nonexistence_checker(name, *find_args)
      create_waiter(name, *find_args)
      create_nonexistence_waiter(name, *find_args)
    end

    def create_helper_method(proposed_method_name, *find_args)
      if find_args.empty?
        create_no_selector(proposed_method_name)
      else
        yield
      end
    end

    def create_existence_checker(element_name, *find_args)
      method_name = "has_#{element_name}?"
      create_helper_method(method_name, *find_args) do
        define_method(method_name) do |*runtime_args|
          wait_time = SitePrism.use_implicit_waits ? Capybara.default_max_wait_time : 0
          Capybara.using_wait_time(wait_time) do
            element_exists?(*self.class.merge_args(find_args, runtime_args))
          end
        end
      end
    end

    def create_nonexistence_checker(element_name, *find_args)
      method_name = "has_no_#{element_name}?"
      create_helper_method(method_name, *find_args) do
        define_method(method_name) do |*runtime_args|
          wait_time = SitePrism.use_implicit_waits ? Capybara.default_max_wait_time : 0
          Capybara.using_wait_time(wait_time) do
            element_does_not_exist?(*self.class.merge_args(find_args, runtime_args))
          end
        end
      end
    end

    def create_waiter(element_name, *find_args)
      method_name = "wait_for_#{element_name}"
      create_helper_method(method_name, *find_args) do
        define_method(method_name) do |timeout = Capybara.default_max_wait_time, *runtime_args|
          begin
            puts "CUSTOM HELPER"
            Waiter.wait_until_true do
              element_exists?(*self.class.merge_args(find_args, runtime_args))
            end
          rescue SitePrism::TimeoutException
            raise SitePrism::TimeOutWaitingForExistenceError, \
              "Timed out after #{timeout}s waiting for #{self.class}##{element_name.to_s}"
          end
        end
      end
    end

    def create_nonexistence_waiter(element_name, *find_args)
      method_name = "wait_for_no_#{element_name}"
      create_helper_method(method_name, *find_args) do
        define_method(method_name) do |timeout = Capybara.default_max_wait_time, *runtime_args|
          begin
            Waiter.wait_until_true do
              element_does_not_exist?(*self.class.merge_args(find_args, runtime_args))
            end
          rescue SitePrism::TimeoutException
            raise SitePrism::TimeOutWaitingForNonExistenceError, \
              "Timed out after #{timeout}s waiting for no #{self.class}##{element_name.to_s}"
          end
        end
      end
    end

    def create_visibility_waiter(element_name, *find_args)
      method_name = "wait_until_#{element_name}_visible"
      create_helper_method(method_name, *find_args) do
        define_method(method_name) do |timeout = Capybara.default_max_wait_time, *runtime_args|
          begin
            Waiter.wait_until_true do
              element_exists?(*self.class.merge_args(find_args, runtime_args, visible: true, wait: timeout))
            end
          rescue SitePrism::TimeoutException
            raise SitePrism::TimeOutWaitingForElementVisibility, \
              "Timed out after #{timeout}s waiting for #{self.class}##{element_name.to_s} to become visible"
          end
        end
      end
    end

    def create_invisibility_waiter(element_name, *find_args)
      method_name = "wait_until_#{element_name}_invisible"
      create_helper_method(method_name, *find_args) do
        define_method(method_name) do |timeout = Capybara.default_max_wait_time, *runtime_args|
          begin
            Waiter.wait_until_true do
              element_does_not_exist?(*self.class.merge_args(find_args, runtime_args, visible: true, wait: timeout))
            end
          rescue SitePrism::TimeoutException
            raise SitePrism::TimeOutWaitingForElementInvisibility, \
              "Timed out after #{timeout}s waiting for #{self.class}##{element_name.to_s} to become invisible"
          end
        end
      end
    end

    def create_no_selector(method_name)
      define_method(method_name) do
        raise SitePrism::NoSelectorForElement.new, "#{self.class.name} => :#{method_name} needs a selector"
      end
    end

    def deduce_iframe_scope_find_args(args)
      case args[0]
      when Integer
        [args[0]]
      when String
        [:css, args[0]]
      else
        args
      end
    end

    def deduce_iframe_element_find_args(args)
      case args[0]
      when Integer
        "iframe:nth-of-type(#{args[0] + 1})"
      when String
        [:css, args[0]]
      else
        args
      end
    end

    def extract_section_options(args, &block)
      if args.first.is_a?(Class)
        klass = args.shift
        section_class = klass if klass.ancestors.include?(SitePrism::Section)
      end

      section_class = deduce_section_class(section_class, &block)
      arguments = deduce_search_arguments(section_class, args)
      [section_class, arguments]
    end

    def deduce_section_class(base_class, &block)
      klass = base_class

      klass = Class.new(klass || SitePrism::Section, &block) if block_given?

      unless klass
        raise ArgumentError, "You should provide descendant of SitePrism::Section \
class or/and a block as the second argument."
      end
      klass
    end

    def deduce_search_arguments(section_class, args)
      extract_search_arguments(args) ||
        extract_search_arguments(section_class.default_search_arguments) ||
        raise(ArgumentError, "You should provide search arguments \
in section creation or set_default_search_arguments within section class")
    end

    def extract_search_arguments(args)
      args if args && !args.empty?
    end
  end
end
