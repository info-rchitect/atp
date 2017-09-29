require 'ast'
module ATP
  # The base processor, this provides a default handler for
  # all node types and will not make any changes to the AST,
  # i.e. an equivalent AST will be returned by the process method.
  #
  # Child classes of this should be used to implement additional
  # processors to modify or otherwise work with the AST.
  #
  # @see http://www.rubydoc.info/gems/ast/2.0.0/AST/Processor
  class Processor
    include ::AST::Processor::Mixin

    def run(node)
      process(node)
    end

    def process(node)
      if node.respond_to?(:to_ast)
        super(node)
      else
        node
      end
    end

    # Some of our processors remove a wrapping node from the AST, returning
    # a node of type :inline containing the children which should be inlined.
    # Here we override the default version of this method to deal with handlers
    # that return an inline node in place of a regular node.
    def process_all(nodes)
      results = []
      nodes.to_a.each do |node|
        n = process(node)
        if n.respond_to?(:type) && n.type == :inline
          results += n.children
        else
          results << n
        end
      end
      results
    end

    def handler_missing(node)
      node.updated(nil, process_all(node.children))
    end

    def n(type, children)
      ATP::AST::Node.new(type, children)
    end

    def n0(type)
      n(type, [])
    end

    def n1(type, arg)
      n(type, [arg])
    end

    def n2(type, arg1, arg2)
      n(type, [arg1, arg2])
    end
  end
end
