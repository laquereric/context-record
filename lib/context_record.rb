# frozen_string_literal: true

require_relative "context_record/version"
require_relative "context_record/context_primitive"
require_relative "context_record/record"

# ContextRecord — typed JSON-LD message envelope and primitive.
#
# Quick start:
#   require "context_record"
#
#   p = ContextRecord::ContextPrimitive.new(type: "vv:Action", value: "read")
#   r = ContextRecord::Record.new(action: :read, target: "users", payload: { filter: p })
#   r.to_json_ld  # deterministic JSON-LD Hash
module ContextRecord
end
