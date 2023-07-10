{% if flag?(:preview_mt) %}
  require "./generic_actor_mt.cr"
{% else %}
  require "./generic_actor_no_mt.cr"
{% end %}
