require 'redis'

module TonalityAnalyser

  # Refactor: work to Redis !
  #   Redis ! Redis ! Redis ! Redis ! Redis ! :)
  class Engine
    TONALITIES = [:pos, :neg]
    attr_reader :counted_words, :probabilites
    REDIS_PREFIX = 'tonality_analyser'
    def initialize
      @redis = Redis.new
      @redis.flushall
      # @total_words = {}
      # @total_words[:all] = 0
      # @total_words[:pos] = 0
      # @total_words[:neg] = 0
      # @counted_words = {}
      # @counted_words[:pos] = {}
      # @counted_words[:neg] = {}
      # @probabilites = {}
      # @probabilites[:pos] = {}
      # @probabilites[:neg] = {}
      # @spec_probabilites = {}
      # @spec_probabilites[:pos] = {}
      # @spec_probabilites[:neg] = {}
    end
    def redis_key(name)
      "#{REDIS_PREFIX}:#{name}"
    end
    def train(words, tonality)
      raise "Invalid tonality '#{tonality}'" unless TONALITIES.include?(tonality)
      words.split.each do |w|
        word = Helpers::Text.normalize(w)
        # @total_words[:all] += 1
        @redis.incr redis_key("total_words")
        # @counted_words[tonality][word] = @counted_words[tonality].include?(word) ? @counted_words[tonality][word]+1 : 1
        @redis.incr redis_key("words:#{tonality}:#{word}")
      end
    end
    def compute_probabilities!
      # TODO: Refactor this :)
      # @counted_words[:pos].each do |word, count|
      #   @probabilites[:pos][word] = @counted_words[:pos][word].to_f / (@counted_words[:pos][word].to_f + @counted_words[:neg][word].to_f)
      #   @spec_probabilites[:pos][word] = @probabilites[:pos][word]
      # end

      # TODO: use "multi redis"
      @redis.keys(redis_key("words:pos:*")).each do |key|
        count = @redis.get(key)
        word = key[redis_key('words:pos:').length..key.length]
        a = @redis.get(redis_key("words:pos:#{word}")).to_f
        b = @redis.get(redis_key("words:neg:#{word}")).to_f
        p = a / (a + b)
        puts "#{word} : #{p}"
        @redis.set redis_key('probabilites:pos:#{word}'), p
        @redis.set redis_key('spec_probabilites:pos:#{word}'), p
      end

      # @counted_words[:neg].each do |word, count|
      #   @probabilites[:neg][word] = @counted_words[:neg][word].to_f / (@counted_words[:pos][word].to_f + @counted_words[:neg][word].to_f)
      #   @spec_probabilites[:neg][word] = @probabilites[:neg][word]
      # end
      @redis.keys(redis_key("words:neg:*")).each do |key|
        count = @redis.get(key)
        word = key[redis_key('words:neg:').length..key.length]
        a = @redis.get(redis_key("words:neg:#{word}")).to_f
        b = @redis.get(redis_key("words:pos:#{word}")).to_f
        p = a / (a + b)
        @redis.set redis_key('probabilites:neg:#{word}'), p
        @redis.set redis_key('spec_probabilites:neg:#{word}'), p
      end
    end
    def analysis(text, tonality)
      num, den1, den2 = 1.0, 1.0, 1.0

      words = Helpers::Text.clean_words_from(text)
      words.each do |word|
        # @spec_probabilites[tonality][word] ||= 0.01
        p = @redis.get(redis_key("spec_probabilites:#{tonality}:#{word}")) || 0.01
        # num *= @spec_probabilites[tonality][word]
        num *= p.to_f
      end
      num *= 0.5
      words.each do |word|
        # @probabilites[tonality][word] ||= 0.01
        p = @redis.get(redis_key("probabilites:#{tonality}:#{word}")) || 0.01
        # den1 *= @probabilites[tonality][word]
        den1 *= p.to_f
      end
      words.each do |word|
        # den2 *= (1 - @probabilites[tonality][word])
        p = @redis.get(redis_key("probabilites:#{tonality}:#{word}"))
        den2 *= (1 - p.to_f)
      end
      proba_pol = num / (den1 + den2)
      proba_pol = 0.0 if proba_pol.nan?
      proba_pol
    end
    def tonality(text)
      pos_proba = analysis(text, :pos)
      neg_proba = analysis(text, :neg)
      pos_proba >= neg_proba ? :pos : :neg
    end
    def load_traning_corpus!(dir)
      TONALITIES.each { |tonality| load_traning_corpus_for(dir, tonality) }
    end
    def load_traning_corpus_for(dir, tonality)
      File.open("#{dir}/#{tonality}.txt", 'r') do |f|
        f.each_line { |line| train(line, tonality) }
        f.close
      end
    end
  end
end
