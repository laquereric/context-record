# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module ContextRecord
  # Domain-agnostic LLM client for local llama.cpp server.
  #
  # Uses OpenAI-compatible API (/v1/chat/completions, /health).
  # Reads LOCAL_LLM_PROVIDER from ENV for server binary location.
  #
  # Usage:
  #   client = LlmClient.new(url: "http://localhost:8081")
  #   client.chat("You are a product expert.", "What lens fits the Canon R5?")
  class LlmClient
    attr_reader :name, :url

    def initialize(url:, name: nil, timeout: 60)
      @url = url
      @name = name || url
      @timeout = timeout
    end

    # Send a chat completion request.
    # @param system_prompt [String] system message
    # @param user_message [String] user message
    # @param max_tokens [Integer]
    # @param temperature [Float]
    # @return [String] assistant response content
    def chat(system_prompt, user_message, max_tokens: 256, temperature: 0.1)
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ]
      request_completion(messages, max_tokens: max_tokens, temperature: temperature)
    end

    # Multi-turn conversation.
    # @param messages [Array<Hash>] [{role: "system"|"user"|"assistant", content: "..."}]
    # @param max_tokens [Integer]
    # @param temperature [Float]
    # @return [String] assistant response content
    def conversation(messages, max_tokens: 256, temperature: 0.1)
      request_completion(messages, max_tokens: max_tokens, temperature: temperature)
    end

    # Streaming chat — yields each token as it arrives.
    # Returns {content:, ttfs:, total:, tokens:} after stream completes.
    #
    # @param system_prompt [String]
    # @param user_message [String]
    # @param max_tokens [Integer]
    # @param temperature [Float]
    # @yield [String] each content chunk as it arrives
    # @return [Hash] {content:, ttfs:, total:, tokens:}
    def chat_stream(system_prompt, user_message, max_tokens: 256, temperature: 0.1, &block)
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ]
      stream_completion(messages, max_tokens: max_tokens, temperature: temperature, &block)
    end

    # Check if the server is online.
    # @return [Boolean]
    def online?
      uri = URI("#{@url}/health")
      resp = Net::HTTP.get_response(uri)
      resp.code == "200"
    rescue StandardError
      false
    end

    # Create a client from environment variables.
    #
    # Single-server mode (Gemma 4): LLM_PORT=8080 → both roles use same port.
    # Legacy two-server mode: QWEN_14B_URL set → conductor:8080, sme:8081.
    #
    # @param role [Symbol] :conductor or :sme
    def self.from_env(role: :sme)
      # Legacy mode: explicit URLs override everything
      if role == :sme && ENV["QWEN_14B_URL"]
        return new(url: ENV["QWEN_14B_URL"], name: "sme", timeout: 120)
      end
      if role == :conductor && ENV["LLAMA_8B_URL"]
        return new(url: ENV["LLAMA_8B_URL"], name: "conductor", timeout: 30)
      end

      # Single-server mode (default): both roles use LLM_PORT
      port = ENV.fetch("LLM_PORT", "8080").to_i
      timeout = role == :conductor ? 30 : 120
      new(url: "http://localhost:#{port}", name: role.to_s, timeout: timeout)
    end

    private

    def request_completion(messages, max_tokens:, temperature:)
      uri = URI("#{@url}/v1/chat/completions")
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req.body = JSON.generate({
        messages: messages,
        max_tokens: max_tokens,
        temperature: temperature
      })

      resp = Net::HTTP.start(uri.hostname, uri.port, read_timeout: @timeout) do |http|
        http.request(req)
      end

      unless resp.code == "200"
        raise "LLM request failed (#{resp.code}): #{resp.body}"
      end

      data = JSON.parse(resp.body)
      data.dig("choices", 0, "message", "content") || raise("No content in LLM response")
    end

    def stream_completion(messages, max_tokens:, temperature:)
      uri = URI("#{@url}/v1/chat/completions")
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req.body = JSON.generate({
        messages: messages,
        max_tokens: max_tokens,
        temperature: temperature,
        stream: true
      })

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ttfs = nil
      content = +""
      tokens = 0

      Net::HTTP.start(uri.hostname, uri.port, read_timeout: @timeout) do |http|
        http.request(req) do |resp|
          unless resp.code == "200"
            raise "LLM stream failed (#{resp.code}): #{resp.read_body}"
          end

          resp.read_body do |chunk|
            chunk.each_line do |line|
              line = line.strip
              next if line.empty?
              next unless line.start_with?("data: ")

              data = line.sub("data: ", "")
              next if data == "[DONE]"

              parsed = JSON.parse(data)
              delta = parsed.dig("choices", 0, "delta", "content")
              next unless delta

              ttfs ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
              content << delta
              tokens += 1
              yield delta if block_given?
            end
          end
        end
      end

      total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      { content: content, ttfs: ttfs || total, total: total, tokens: tokens }
    end
  end
end
