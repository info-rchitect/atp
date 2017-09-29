module ATP
  module Processors
    # This optimizes the condition nodes such that any adjacent flow nodes that
    # have the same condition, will be grouped together under a single condition
    # wrapper.
    #
    # For example this AST:
    #
    #   (flow
    #     (group
    #       (name "g1")
    #       (test
    #         (name "test1"))
    #       (flow-flag "bitmap" true
    #         (test
    #           (name "test2"))))
    #     (flow-flag "bitmap" true
    #       (group
    #         (name "g1")
    #         (flow-flag "x" true
    #           (test
    #             (name "test3")))
    #         (flow-flag "y" true
    #           (flow-flag "x" true
    #             (test
    #               (name "test4")))))))
    #
    # Will be optimized to this:
    #
    #   (flow
    #     (group
    #       (name "g1")
    #       (test
    #         (name "test1"))
    #       (flow-flag "bitmap" true
    #         (test
    #           (name "test2"))
    #         (flow-flag "x" true
    #           (test
    #             (name "test3"))
    #           (flow-flag "y" true
    #             (test
    #               (name "test4")))))))
    #
    class Condition < Processor
      def on_flow(node)
        node.updated(nil, optimize(process_all(node.children)))
      end

      def on_flow_flag(node)
        flag, state, *nodes = *node
        if conditions_to_remove.any? { |c| node.type == c.type && c.to_a == [flag, state] }
          # This ensures any duplicate conditions matching the current one get removed
          conditions_to_remove << node.updated(nil, [flag, state])
          result = n(:inline, optimize(process_all(nodes)))
          conditions_to_remove.pop
        else
          conditions_to_remove << node.updated(nil, [flag, state])
          result = node.updated(nil, [flag, state] + optimize(process_all(nodes)))
          conditions_to_remove.pop
        end
        result
      end
      alias_method :on_test_result, :on_flow_flag
      alias_method :on_job, :on_flow_flag
      alias_method :on_run_flag, :on_flow_flag
      alias_method :on_test_executed, :on_flow_flag

      def on_group(node)
        name, *nodes = *node
        if conditions_to_remove.any? { |c| node.type == c.type && c.to_a == [name] }
          conditions_to_remove << node.updated(nil, [name])
          result = n(:inline, optimize(process_all(nodes)))
          conditions_to_remove.pop
        else
          conditions_to_remove << node.updated(nil, [name])
          result = node.updated(nil, [name] + optimize(process_all(nodes)))
          conditions_to_remove.pop
        end
        result
      end

      def optimize(nodes)
        results = []
        node1 = nil
        nodes.each do |node2|
          if node1
            if can_be_combined?(node1, node2)
              node1 = process(combine(node1, node2))
            else
              results << node1
              node1 = node2
            end
          else
            node1 = node2
          end
        end
        results << node1 if node1
        results
      end

      def can_be_combined?(node1, node2)
        if condition_node?(node1) && condition_node?(node2)
          !(conditions(node1) & conditions(node2)).empty?
        else
          false
        end
      end

      def condition_node?(node)
        node.respond_to?(:type) &&
          [:flow_flag, :run_flag, :test_result, :group, :job, :test_executed].include?(node.type)
      end

      def combine(node1, node2)
        common = conditions(node1) & conditions(node2)
        common.each { |condition| conditions_to_remove << condition }
        node1 = process(node1)
        node1 = [node1] unless node1.is_a?(Array)
        node2 = process(node2)
        node2 = [node2] unless node2.is_a?(Array)
        common.size.times { conditions_to_remove.pop }

        node = nil
        common.reverse_each do |condition|
          if node
            node = condition.updated(nil, condition.children + [node])
          else
            node = condition.updated(nil, condition.children + node1 + node2)
          end
        end
        node
      end

      def conditions(node)
        result = []
        if [:flow_flag, :run_flag, :test_result, :job, :test_executed].include?(node.type)
          flag, state, *children = *node
          result << node.updated(nil, [flag, state])
          result += conditions(children.first) if children.first
        elsif node.type == :group
          name, *children = *node
          # Sometimes a group can have an ID
          if children.first.try(:type) == :id
            result << node.updated(nil, [name, children.shift])
          else
            result << node.updated(nil, [name])
          end
          result += conditions(children.first) if children.first
        end
        result
      end

      def conditions_to_remove
        @conditions_to_remove ||= []
      end
    end
  end
end
