module GenericActor
  VERSION = "0.2.0"

  macro cast_def(name, args, &block)
    def {{name}}({% if args %}*,{% for k, v in args %}{{k}} : {{v}},{% end %}{% end %}) : Nil
      {{block.body}}
    end
  end

  macro prioritized_cast_def(name, args, &block)
    def {{name}}({% if args %}*,{% for k, v in args %}{{k}} : {{v}},{% end %}{% end %}) : Nil
      {{block.body}}
    end
  end

  macro call_def(name, args, result, &block)
    def {{name}}({% if args %}*,{% for k, v in args %}{{k}} : {{v}},{% end %}{% end %}) 
      {{block.body}}
    end
  end

  macro prioritized_call_def(name, args, result, &block)
    def {{name}}({% if args %}*,{% for k, v in args %}{{k}} : {{v}},{% end %}{% end %})
      {{block.body}}
    end
  end
end
