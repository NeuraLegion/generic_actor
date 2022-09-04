require "log"
require "mutex"

module GenericActor
  VERSION = "0.1.1"

  private enum ActorState
    PENDING
    PROCESSING
    STOPPED
  end

  class AbuseStoppedActorException < Exception
  end

  @message_loop_state = Atomic(ActorState).new(ActorState::PENDING)
  @message_queue = Channel(Message).new(100)
  @was_stop_action_performed = Atomic::Flag.new

  def stop_actor
    test = @message_loop_state.compare_and_set(ActorState::PENDING, ActorState::STOPPED)
    if test.last
      try_process_stop
      @message_queue.close
    elsif test.first == ActorState::PROCESSING 
      @message_loop_state.set(ActorState::STOPPED) 
      @message_queue.close
    end
  end

  protected def process_stop
    # You can override process_stop to close resources you want
  end

  private def try_process_stop
    return unless @was_stop_action_performed.test_and_set
    begin
      process_stop
    rescue e
      Log.error {"Cought exception from process_stop: #{e}"}
    end
  end

  private abstract struct Message
  end

  private def check_message_loop
    case @message_loop_state.get
    when ActorState::PROCESSING
      return
    when ActorState::STOPPED
      raise AbuseStoppedActorException.new
    else
      spawn { actor_loop } if @message_loop_state.compare_and_set(ActorState::PENDING, ActorState::PROCESSING).last
    end
  end

  private def actor_handle(message : Message)
    raise "Unhandled actor message #{message}"
  end

  private def actor_loop
    loop do
      begin
        actor_handle(@message_queue.receive)
      rescue exception : Channel::ClosedError
        return try_process_stop
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
      check_message_loop
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
    {% message_type = "FutureM#{name}".tr("?", "").camelcase.id %}
    private struct {{message_type}} < Message
      @channel = Channel({{result}} | Exception).new(1)

      {% if args %}
      getter args : NamedTuple({% for k, v in args %}{{k}}: {{v}},{% end %})

      def initialize(@args)
      end
      {% end %}

      def set_response(response : {{result}}) : Nil
        @channel.send(response)
      end

      def set_exception(exception : Exception) : Nil
        @channel.send(exception)
      end

      # can raise Channel::ClosedError after stop_actor
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
      check_message_loop  
      future = {{message_type}}.new({% if args %}{ {% for k, v in args %}{{k}}: {{k}},{% end %} }{% end %})
      @message_queue.send(future)
      future.await
    end

    protected def process_{{name}}(__m : {{message_type}}) : {{result}}
      {% if args %}
      {% for k, v in args %}
      {{k.id}} = __m.args[{{k.symbolize}}]
      {% end %}
      {% end %}
      {{ block.body }}
    end

    private def actor_handle(future : {{message_type}})
      future.set_response(process_{{name}}(future))
    rescue e
      future.set_exception(e)
    end
  end
end
