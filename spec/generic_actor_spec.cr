require "./spec_helper"
require "log"

class Counter
  include GenericActor
  Log = ::Log.for(self)

  @value = 0

  def initialize(@name : String = "777")
    print @name
  end

  cast_def reset, nil do
    @value = 0
  end

  cast_def add, {amount: Int32} do
    raise ArgumentError.new("Negative amount are not allowed") unless amount >= 0
    @value += amount
  end

  call_def get, nil, Int32 do
    @value
  end

  call_def get_alt, {amount: Int32}, Int32 do
    raise ArgumentError.new("Negative amount are not allowed") unless amount >= 0
    @value + amount
  end

  call_def zero?, nil, Bool do
    @value == 0
  end

  cast_def question?, nil do
    # Check if cast can end with ?
  end

  call_def many_args_call, {a: Int32, b: Int32}, Int32 do
    a + b
  end

  cast_def many_args_cast, {a: Int32, b: Int32} do
  end
end

describe GenericActor do
  it "serialize messages" do
    c = Counter.new
    c.reset

    done = Channel(Bool).new
    4.times do
      spawn do
        # for mt this will attempt to run each 25.times loop in a different thread
        25.times do
          c.add amount: 1
        end
        done.send(true)
      end
    end
    4.times { done.receive }

    c.get.should eq(100)
  end

  it "handle exceptions in calls" do
    c = Counter.new
    expect_raises(ArgumentError) do
      c.get_alt amount: -10
    end
  end

  it "compiles with ?" do
    c = Counter.new
    c.question?
    c.zero?
  end

  it "compiles with multiple args" do
    c = Counter.new
    c.many_args_call(a: 1, b: 2)
    c.many_args_cast(a: 1, b: 2)
  end
end
