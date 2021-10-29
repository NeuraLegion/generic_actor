require "log"

module GenericActor
  VERSION = "0.1.0"

  @message_queue = Channel(Message).new(100)

  private abstract struct Message
  end

  private def actor_handle(message : Message)
    raise "Unhandled actor message #{message}"
  end
  
  def initialize
    spawn do
      actor_loop
    end
  end

  def actor_loop
    # TODO handle stop
    loop do
      message = @message_queue.receive
      actor_handle(message)
    end
  end

  macro cast_def(name, args, &block)
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
      @message_queue.send(message)
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

  macro call_def(name, args, result, &block)
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
      @message_queue.send(message)
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
