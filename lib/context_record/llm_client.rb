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
    def chat(system_prompt, user_message, max_tokens: 1024, temperature: 0.1)
      uri = URI("#{@url}/v1/chat/completions")
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req.body = JSON.generate({
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_message }
        ],
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

    # Multi-turn conversation.
    # @param messages [Array<Hash>] [{role: "system"|"user"|"assistant", content: "..."}]
    # @param max_tokens [Integer]
    # @param temperature [Float]
    # @return [String] assistant response content
    def conversation(messages, max_tokens: 1024, temperature: 0.1)
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

    # Check if the server is online.
    # @return [Boolean]
    def online?
      uri = URI("#{@url}/health")
      resp = Net::HTTP.get_response(uri)
      resp.code == "200"
    rescue StandardError
      false
    end

    # Create a client from LOCAL_LLM_PROVIDER env var defaults.
    # @param role [Symbol] :conductor (8080) or :sme (8081)
    def self.from_env(role: :sme)
      port = role == :conductor ? 8080 : 8081
      timeout = role == :conductor ? 30 : 120
      new(url: "http://localhost:#{port}", name: role.to_s, timeout: timeout)
    end
  end
end
