require "log"

module GenericActor
  VERSION = "0.1.0"

  getter prioritized_calls : Atomic(Int64) = Atomic(Int64).new(0)
  getter calls : Atomic(Int64) = Atomic(Int64).new(0)

  @message_loop_started = Atomic::Flag.new
  @message_queue = Channel(Message).new(100)
  @priority_message_queue = Channel(Message).new(100)

  private def check_message_loop
    return unless @message_loop_started.test_and_set
    spawn { actor_loop }
  end

  private abstract struct Message
  end

  private def actor_handle(message : Message)
    raise "Unhandled actor message #{message}"
  end

  def actor_loop
    loop do
      select
      when message = @priority_message_queue.receive
        @prioritized_calls.add(1)
        actor_handle(message)
      when message = @message_queue.receive
        @calls.add(1)
        actor_handle(message)
      end
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
      check_message_loop
      {% if args %}
        {% if args[:priority] %}
          { @priority_message_queue.send(message) }
        {% else %}
          { @message_queue.send(message) }
        {% end %}
      {% else %}
        { @message_queue.send(message) }
      {% end %}
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
      check_message_loop
      {% if args %}
        {% if args[:priority] %}
          { @priority_message_queue.send(message) }
        {% else %}
          { @message_queue.send(message) }
        {% end %}
      {% else %}
        { @message_queue.send(message) }
      {% end %}
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
