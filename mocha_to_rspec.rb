# Rewrite mocha mocks to rspec-mocks format

# Unsolved cases:
#
# multiple_yields: has no exact analogue. You have to call and_yield multiple
#                  times, which could only be translated in this script if
#                  passed a literal array.
# optionally: not directly supported, but also sort of dumb. This will remove it
#             and you can find out whether the argument was really optional or
#             not.
# yaml_equivalent: who cares
# generalized Not: we only have it with include so i've only implemented that

# XXX Block translation is a problem, in rspec there have to be assertions in the block, not just a boolean return

# MONKEY PATCH
# see https://github.com/whitequark/parser/issues/283
# We have a lot of strings like this
class Parser::Builders::Default
  def string_value(token)
    value(token)
  end
end


class MochaToRspec < Parser::TreeRewriter
  def on_send(node)
    arguments = node.children[2..-1]
    if node.children[0].nil?
      case node.children[1]
      when :mock, :stub
        replace(node.location.selector, 'double')
      when :stub_everything
        if arguments.empty?
          replace(node.location.expression, "double.as_null_object")
        else
          range = arguments.first.loc.expression.join(arguments.last.loc.expression)
          replace(node.location.expression, "double.(#{range.source}).as_null_object")
        end
      when :sequence
        # These are unnecessary, remove the whole line
        # this is an assumption I've verified for our code base, don't reuse
        remove(node.loc.expression.source_buffer.line_range(node.loc.expression.line))
      end
    else
      case node.children[1]
      when :expects
        replace(node.loc.expression, rewrite_expectation(node, 'expects'))
      when :stubs
        replace(node.loc.expression, rewrite_expectation(node, 'stubs'))
      when :unstub
        replace(node.loc.expression, rewrite_expectation(node, 'stubs') + '.and_call_original')
      when :stub_everything
        replace(node.loc.selector, 'as_null_object')
      when :returns
        replace(node.loc.selector, 'and_return')
      when :yields
        replace(node.loc.selector, 'and_yield')
      when :raises
        replace(node.loc.selector, 'and_raise')
      when :at_least_once
        range = node.loc.selector.join(node.loc.expression.end)
        replace(range, 'at_least(:once)')
      when :at_most_once
        range = node.loc.selector.join(node.loc.expression.end)
        replace(range, 'at_most(:once)')
      when :times
        # Check for an argument to distinguish from integer#times
        if node.children[2]
          replace(node.loc.selector.join(node.loc.expression.end),
                  "exactly(#{node.children[2].loc.expression.source}).times")
        end
      when :in_sequence
        range = node.loc.selector.join(node.loc.expression.end)
        replace(range, 'ordered')
      when :with
        # For block implementation we remove the `with`
        if arguments.empty?
          remove(node.loc.dot)
          remove(node.loc.selector)
          remove(node.loc.begin) if node.loc.begin
          remove(node.loc.end) if node.loc.end
        else
          arguments.each do |argument|
            rewrite_expectation_matcher!(argument)
          end
        end
        # convert argument matchers
      else
        nil
      end
    end
    super
  end

  private

  def rewrite_expectation(node, expects_or_stubs)
    method = case expects_or_stubs
             when 'expects' then 'expect'
             when 'stubs' then 'allow'
             else
               raise ArgumentError, "expects_or_stubs must be expects or stubs"
             end
    if node.children[0]&.children&.at(1) == :any_instance
      mocked_expression = node.children[0].children[0].loc.expression
      allow_clause = "#{method}_any_instance_of(#{mocked_expression.source})"
    else
      mocked_expression = node.children[0].loc.expression
      allow_clause = "#{method}(#{mocked_expression.source})"
    end
    "#{allow_clause}.to receive(#{node.children[2].loc.expression.source})"
  end

  def rewrite_expectation_matcher!(node)
    return nil unless node.type == :send
    case node.children[1]
    when :all_of
      rewrite_all_of(node)
    when :any_of
      replace(node.loc.selector, 'include')
      node.children[2..-1].each do |child|
        rewrite_expectation_matcher!(child)
      end
    when :any_parameters
      replace(node.loc.selector, 'any_args')
    when :anything
      # noop
    when :equals
      replace(node.loc.selector, 'equal')  # XXX Is this really equivalent?
    when :equivalent_uri
      # You're on your own
    when :has_entries
      replace(node.loc.selector, 'hash_including')
    when :has_entry
      replace(node.loc.selector, 'hash_including')
      # XXX rewrite arguments to be a hash
    when :has_equivalent_query_string
      # You're on your own
    when :has_key
      replace(node.loc.selector, 'include')  # Can be better english?
    when :has_value
      # nope
    when :includes
      replace(node.loc.selector, 'include')  # Necessary???
    when :instance_of
      # noop
    when :is_a
      replace(node.loc.selector, 'kind_of')
    when :kind_of
      # noop
    when :Not
      replace(node.loc.selector, 'not')  # I hope?
      rewrite_expectation_matcher!(node.children[2])
    when :optionally
      unwrap_send(node)
      rewrite_expectation_matcher!(node.children[2])
    when :regexp_matches
      # Regexes will match automatically
      unwrap_send(node)
    when :responds_with
      replace(node.loc.selector, 'having_attributes')
      attribute = node.children[2].loc.expression
      value = node.children[3].loc.expression
      replace(attribute.join(value),
             "#{attribute.source} => #{value.source}")
    when :yaml_equivalent
    end
  end

  # Delete a method call by removing the selector and optional parens.
  # Won't work properly if there is a receiver or more than one argument.
  def unwrap_send(node)
    remove(node.loc.selector)
    remove(node.loc.begin) if node.loc.begin
    remove(node.loc.end) if node.loc.end
  end

  def rewrite_all_of(node)
    argument_nodes = node.children[2..-1]
    comma_ranges = []
    argument_nodes.reduce do |last_arg, arg|
      comma_ranges << Parser::Source::Range.new(arg.loc.expression.source_buffer,
                                                last_arg.loc.expression.end_pos,
                                                arg.loc.expression.begin_pos - 1)
      arg
    end
    comma_ranges.each do |range|
      @source_rewriter.replace(range, ' &')
    end
    argument_nodes.each do |a|
      rewrite_expectation_matcher!(a)
    end

    remove(node.loc.selector)
    remove(node.loc.begin)
    remove(node.loc.end)
  end
end
