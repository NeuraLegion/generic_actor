require "log"

module GenericActor
  VERSION = "0.2.0"

  private abstract struct Message
  end

  @message_loop_started = Atomic::Flag.new
  @regular_message_queue = Channel(Message).new(100)
  @priority_message_queue = Channel(Message).new(100)

  private def actor_handle(message : Message) : Nil
    nil
  end

  private def actor_loop
    loop do
      select
      when message = @priority_message_queue.receive
        actor_handle(message)
      when message = @regular_message_queue.receive
        actor_handle(message)
      end
    end
  end

  private def check_message_loop
    return unless @message_loop_started.test_and_set
    spawn { actor_loop }
  end

  macro cast_def(name, args, &block)
    define_cast_def @regular_message_queue, {{name}}, {{args}}, {{ block }}
  end

  macro prioritized_cast_def(name, args, &block)
    define_cast_def @priority_message_queue, {{name}}, {{args}}, {{ block }}
  end

  macro call_def(name, args, result, &block)
    define_call_def @regular_message_queue, {{name}}, {{args}}, {{result}}, {{ block }}
  end

  macro prioritized_call_def(name, args, result, &block)
    define_call_def @priority_message_queue, {{name}}, {{args}}, {{result}}, {{ block }}
  end

  # define message with unique type according method name and his args
  private macro define_cast_def(queue, name, args, &block)
    {% message_type = "M#{name}".tr("?", "").camelcase.id %}
    private struct {{message_type}} < Message
      {% if args %}
      getter args : NamedTuple({% for k, v in args %}{{k}}: {{v}},{% end %})

      def initialize(@args)
      end
      {% end %}
    end

    def {{name}}({% if args %}*,{% for k, v in args %}{{k}} : {{v}},{% end %}{% end %}) : Nil
      message = {{message_type}}.new({% if args %}{ {% for k, v in args %}{{k}}: {{k}},{% end %} }{% end %})
      check_message_loop
      {{queue}}.send(message)
    end

    protected def process_{{name}}(__m : {{message_type}}) : Nil
      {% if args %}
      {% for k, v in args %}
      {{k.id}} = __m.args[{{k.symbolize}}]
      {% end %}
      {% end %}
      {{ block.body }}
    end

    private def actor_handle(message : {{message_type}})
      begin
        process_{{name}}(message)
      rescue e
        Log.error(exception: e) { "Unhandled exception on {{@type}}#{'#'}{{name}}" }
      end
    end
  end

  # define message with unique type according method name and his args
  private macro define_call_def(queue, name, args, result, &block)
    {% message_type = "M#{name}".tr("?", "").camelcase.id %}
    private struct {{message_type}} < Message
      @channel = Channel({{result}} | Exception).new(1)

      {% if args %}
      getter args : NamedTuple({% for k, v in args %}{{k}}: {{v}},{% end %})

      def initialize(@args)
      end
      {% end %}

      def reply_with
        begin
          @channel.send(yield)
        rescue e
          @channel.send(e)
        end
      end

      def await : {{result}}
        res = @channel.receive

        if res.is_a?(::Exception)
          raise res
        else
          res
        end
      end
    end

    def {{name}}({% if args %}*,{% for k, v in args %}{{k}} : {{v}},{% end %}{% end %}) : {{result}}
      message = {{message_type}}.new({% if args %}{ {% for k, v in args %}{{k}}: {{k}},{% end %} }{% end %})
      check_message_loop
      {{queue}}.send(message)
      message.await
    end

    protected def process_{{name}}(__m : {{message_type}}) : {{result}}
      {% if args %}
      {% for k, v in args %}
      {{k.id}} = __m.args[{{k.symbolize}}]
      {% end %}
      {% end %}
      {{ block.body }}
    end

    private def actor_handle(message : {{message_type}})
      message.reply_with { process_{{name}}(message) }
    end
  end
end
