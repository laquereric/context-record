# frozen_string_literal: true

require "ruby_llm"
require "net/http"
require "uri"

module ContextRecord
  # Domain-agnostic LLM client backed by RubyLLM.
  #
  # Uses the OpenAI-compatible provider to talk to a local llama.cpp server.
  # Reads LLM_PORT / LLM_MODEL from ENV; defaults to Gemma 4 on port 8080.
  #
  # Usage:
  #   client = LlmClient.new
  #   client.chat("You are an expert.", "What lens fits the Canon R5?")
  class LlmClient
    attr_reader :name, :url, :model_id

    DEFAULT_MODEL_ID = "gemma4-local"
    DEFAULT_PORT = 8080

    def initialize(url: nil, name: nil, model_id: DEFAULT_MODEL_ID, timeout: 120)
      port = ENV.fetch("LLM_PORT", DEFAULT_PORT.to_s).to_i
      @url = url || "http://localhost:#{port}"
      @name = name || model_id
      @model_id = model_id
      @timeout = timeout
      ensure_configured!
    end

    # Send a chat completion request via RubyLLM.
    def chat(system_prompt, user_message, max_tokens: 512, temperature: 0.1)
      c = new_chat(max_tokens: max_tokens, temperature: temperature)
      c.with_instructions(system_prompt)
      response = c.ask(user_message)
      response.content || raise("No content in LLM response")
    end

    # Streaming chat — yields each token as it arrives.
    # @yield [Hash] {type: :content, text: "..."}
    # @return [Hash] {content:, reasoning:, ttfs:, ttfs_content:, total:, tokens:}
    def chat_stream(system_prompt, user_message, max_tokens: 512, temperature: 0.1)
      c = new_chat(max_tokens: max_tokens, temperature: temperature)
      c.with_instructions(system_prompt)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ttfs = nil
      ttfs_content = nil
      content = +""
      reasoning = +""
      tokens = 0

      response = c.ask(user_message) do |chunk|
        tokens += 1
        text = chunk.content
        if text && !text.empty?
          ttfs ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          ttfs_content ||= ttfs
          content << text
          yield({ type: :content, text: text }) if block_given?
        end
      end

      # Fall back to final response if streaming didn't produce content
      if content.empty? && response&.content
        content = response.content
      end

      total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      {
        content: content,
        reasoning: reasoning,
        ttfs: ttfs || total,
        ttfs_content: ttfs_content,
        total: total,
        tokens: tokens
      }
    end

    # Multi-turn conversation.
    def conversation(messages, max_tokens: 512, temperature: 0.1)
      c = new_chat(max_tokens: max_tokens, temperature: temperature)
      messages.each do |msg|
        c.with_instructions(msg[:content]) if msg[:role].to_s == "system"
      end
      user_msg = messages.reverse.find { |m| m[:role].to_s == "user" }
      response = c.ask(user_msg[:content])
      response.content || raise("No content in LLM response")
    end

    # Health check via HTTP (not RubyLLM — needs raw endpoint).
    def online?
      uri = URI("#{@url}/health")
      resp = Net::HTTP.get_response(uri)
      resp.code == "200"
    rescue StandardError
      false
    end

    # Create from environment variables.
    # Single-server (Gemma 4): LLM_PORT → both roles on same port.
    # Legacy: QWEN_14B_URL / LLAMA_8B_URL → explicit two-server mode.
    def self.from_env(role: :sme)
      if role == :sme && ENV["QWEN_14B_URL"]
        return new(url: ENV["QWEN_14B_URL"], name: "sme")
      end
      if role == :conductor && ENV["LLAMA_8B_URL"]
        return new(url: ENV["LLAMA_8B_URL"], name: "conductor", timeout: 30)
      end

      port = ENV.fetch("LLM_PORT", DEFAULT_PORT.to_s).to_i
      model = ENV.fetch("LLM_MODEL", DEFAULT_MODEL_ID)
      timeout = role == :conductor ? 30 : 120
      new(url: "http://localhost:#{port}", name: role.to_s, model_id: model, timeout: timeout)
    end

    private

    def new_chat(max_tokens: 512, temperature: 0.1)
      RubyLLM.chat(model: @model_id).tap do |c|
        c.with_temperature(temperature) if c.respond_to?(:with_temperature)
      end
    end

    def ensure_configured!
      configure_ruby_llm!
      register_local_model!
    end

    def configure_ruby_llm!
      RubyLLM.configure do |c|
        c.openai_api_key = ENV.fetch("OPENAI_API_KEY", "local")
        c.openai_api_base = "#{@url}/v1"
      end
    end

    def register_local_model!
      models = RubyLLM.models.instance_variable_get(:@models)
      return if models&.any? { |m| m.id == @model_id }

      info = RubyLLM::Model::Info.new(
        id: @model_id,
        name: @model_id,
        provider: "openai",
        family: "local",
        created_at: Time.now,
        context_window: 65536,
        max_output_tokens: 4096,
        modalities: { input: ["text"], output: ["text"] },
        capabilities: { streaming: true },
        pricing: { input_per_million: 0, output_per_million: 0 },
        metadata: {}
      )
      models << info
    end
  end
end
