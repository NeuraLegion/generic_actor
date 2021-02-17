# generic_actor

Generic Actor to build MT safe objects

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     generic_actor:
       github: NeuraLegion/generic_actor
   ```

2. Run `shards install`

## Usage

```crystal
require "generic_actor"
```

A simple object can look as follows:

```crystal
  class StringStore
    include GenericActor

    @db = Array(String).new

    call_def get, nil, Array(String) do
      @db.dup
    end

    cast_def set, {string: String} do
      @db << string
    end

    call_def includes?, {string: String}, Bool do
      @db.includes?(string)
    end

    call_def size, nil, Int32 do
      @db.size
    end
  end
```

And the usage can be like:

```crystal
string_store = StringStore.new
100.times do
  spawn do
    string_store.set("adding new string")
    string_store.size # what's the size?
  end
end
```

## Contributing

1. Fork it (<https://github.com/NeuraLegion/generic_actor/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
