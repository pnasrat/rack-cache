require "#{File.dirname(__FILE__)}/spec_setup"

class MockResponse < Rack::MockResponse
  include Rack::Cache::Headers
  include Rack::Cache::ResponseHeaders
  public :now
end

describe 'Rack::Cache::Headers' do
  before :each do
    @now = Time.httpdate(Time.now.httpdate)
    @res = MockResponse.new(200, {'Date' => @now.httpdate}, '')
    @one_hour_ago = Time.httpdate((Time.now - (60**2)).httpdate)
  end
  after :each do
    @now, @res, @one_hour_ago = nil
  end

  describe '#cache_control' do
    it 'handles single name=value pair' do
      @res.headers['Cache-Control'] = 'max-age=600'
      @res.cache_control['max-age'].should.equal '600'
    end
    it 'handles multiple name=value pairs' do
      @res.headers['Cache-Control'] = 'max-age=600, max-stale=300, min-fresh=570'
      @res.cache_control['max-age'].should.equal '600'
      @res.cache_control['max-stale'].should.equal '300'
      @res.cache_control['min-fresh'].should.equal '570'
    end
    it 'handles a single flag value' do
      @res.headers['Cache-Control'] = 'no-cache'
      @res.cache_control.should.include 'no-cache'
      @res.cache_control['no-cache'].should.be true
    end
    it 'handles a bunch of all kinds of stuff' do
      @res.headers['Cache-Control'] = 'max-age=600,must-revalidate,min-fresh=3000,foo=bar,baz'
      @res.cache_control['max-age'].should.equal '600'
      @res.cache_control['must-revalidate'].should.be true
      @res.cache_control['min-fresh'].should.equal '3000'
      @res.cache_control['foo'].should.equal 'bar'
      @res.cache_control['baz'].should.be true
    end
    it 'removes the header when given an empty hash' do
      @res.headers['Cache-Control'] = 'max-age=600, must-revalidate'
      @res.cache_control['max-age'].should.equal '600'
      @res.cache_control = {}
      @res.headers.should.not.include 'Cache-Control'
    end
    it 'strips leading and trailing spaces from header value' do
      @res.headers['Cache-Control'] = ' public '
      @res.cache_control.should.include 'public'
    end
  end
end

describe 'Rack::Cache::ResponseHeaders' do
  before :each do
    @now = Time.httpdate(Time.now.httpdate)
    @one_hour_ago = Time.httpdate((Time.now - (60**2)).httpdate)
    @one_hour_later = Time.httpdate((Time.now + (60**2)).httpdate)
    @res = MockResponse.new(200, {'Date' => @now.httpdate}, '')
  end
  after :each do
    @now, @res, @one_hour_ago = nil
  end

  describe '#validateable?' do
    it 'is true when Last-Modified header present' do
      @res = MockResponse.new(200, { 'Last-Modified' => @one_hour_ago.httpdate }, '')
      @res.extend Rack::Cache::ResponseHeaders
      @res.should.be.validateable
    end
    it 'is true when Etag header present' do
      @res = MockResponse.new(200, { 'Etag' => '"12345"' }, '')
      @res.extend Rack::Cache::ResponseHeaders
      @res.should.be.validateable
    end
    it 'is false when no validator is present' do
      @res = MockResponse.new(200, {}, '')
      @res.extend Rack::Cache::ResponseHeaders
      @res.should.not.be.validateable
    end
  end

  describe '#date' do
    it 'uses the Date header if present' do
      @res = MockResponse.new(200, { 'Date' => @one_hour_ago.httpdate }, '')
      @res.extend Rack::Cache::ResponseHeaders
      @res.date.should.equal @one_hour_ago
    end
    it 'uses the current time when no Date header present' do
      @res = MockResponse.new(200, {}, '')
      @res.extend Rack::Cache::ResponseHeaders
      @res.date.should.be.close Time.now, 1
    end
    it 'returns the correct date when the header is modified directly' do
      @res = MockResponse.new(200, { 'Date' => @one_hour_ago.httpdate }, '')
      @res.extend Rack::Cache::ResponseHeaders
      @res.date.should.equal @one_hour_ago
      @res.headers['Date'] = @now.httpdate
      @res.date.should.equal @now
    end
  end

  describe '#expires_at' do
    it 'returns #date + #max_age when Cache-Control/max-age is present' do
      @res.headers['Cache-Control'] = 'max-age=500'
      @res.expires_at.should.equal @res.date + 500
    end
    it 'uses the Expires header when present and no Cache-Control/max-age' do
      @res.headers['Expires'] = @one_hour_ago.httpdate
      @res.expires_at.should.equal @one_hour_ago
    end
    it 'returns nil when no Expires or Cache-Control provided' do
      @res.expires_at.should.be nil
    end
  end

  describe '#max_age' do
    it 'uses s-maxage cache control directive when present' do
      @res.headers['Cache-Control'] = 's-maxage=600, max-age=0'
      @res.max_age.should.equal 600
    end
    it 'falls back to max-age when no s-maxage directive present' do
      @res.headers['Cache-Control'] = 'max-age=600'
      @res.max_age.should.equal 600
    end
    it 'falls back to Expires when no max-age or s-maxage directive present' do
      @res.headers['Cache-Control'] = 'must-revalidate'
      @res.headers['Expires'] = @one_hour_later.httpdate
      @res.max_age.should.equal 60 ** 2
    end
    it 'gives a #max_age of nil when no freshness information available' do
      @res.max_age.should.be.nil
    end
  end

  describe '#freshness_information?' do
    it 'is true when Expires header is present' do
      @res.headers['Expires'] = Time.now.httpdate
      @res.freshness_information?.should.be true
    end
    it 'is true when a Cache-Control max-age directive is present' do
      @res.headers['Cache-Control'] = 'max-age=500'
      @res.freshness_information?.should.be true
    end
    it 'is true when a Cache-Control s-maxage directive is present' do
      @res.headers['Cache-Control'] = 's-maxage=500'
      @res.freshness_information?.should.be true
    end
    it 'is not true otherwise' do
      @res.freshness_information?.should.be false
    end
  end

  describe '#public=' do
    it 'adds the public Cache-Control directive when set true' do
      @res.headers['Cache-Control'] = 'max-age=100'
      @res.public = true
      @res.headers['Cache-Control'].should.equal 'public, max-age=100'
    end
    it 'removes the private Cache-Control directive' do
      @res.headers['Cache-Control'] = 'private, max-age=100'
      @res.public = true
      @res.headers['Cache-Control'].should.equal 'public, max-age=100'
    end
  end

  describe '#public?' do
    it 'is true when the public directive is present' do
      @res.headers['Cache-Control'] = 'public'
      @res.should.be.public
    end
    it 'is false when only the private directive is present' do
      @res.headers['Cache-Control'] = 'private'
      @res.should.not.be.public
    end
    it 'is false when no Cache-Control header is present' do
      @res.should.not.be.public
    end
  end

  describe '#private=' do
    it 'adds the private Cache-Control directive when set true' do
      @res.headers['Cache-Control'] = 'max-age=100'
      @res.private = true
      @res.headers['Cache-Control'].should.equal 'private, max-age=100'
    end
    it 'removes the public Cache-Control directive' do
      @res.headers['Cache-Control'] = 'public, max-age=100'
      @res.private = true
      @res.headers['Cache-Control'].should.equal 'private, max-age=100'
    end
  end

  describe '#private?' do
    it 'is true when the private directive is present' do
      @res.headers['Cache-Control'] = 'private'
      @res.should.be.private
    end
    it 'is false when the private directive is not present' do
      @res.headers['Cache-Control'] = 'public'
      @res.should.not.be.private
    end
    it 'is false when no Cache-Control header is present' do
      @res.should.not.be.private
    end
  end

  describe '#no_cache?' do
    it 'is true when a Cache-Control no-cache directive is present' do
      @res.headers['Cache-Control'] = 'no-cache'
      assert @res.no_cache?
    end
    it 'is false otherwise' do
      assert !@res.no_cache?
    end
  end

  describe '#must_revalidate?' do
    it 'is true when a Cache-Control must-revalidate directive is present' do
      @res.headers['Cache-Control'] = 'private, must-revalidate'
      assert @res.must_revalidate?
    end
    it 'is true when a Cache-Control proxy-revalidate directive is present' do
      @res.headers['Cache-Control'] = 'public, proxy-revalidate'
      assert @res.must_revalidate?
    end
    it 'is false otherwise' do
      assert !@res.must_revalidate?
    end
  end

  describe '#stale?' do
    it 'is true when TTL cannot be established' do
      @res.should.be.stale
    end
    it 'is false when the TTL is <= 0' do
      @res.headers['Expires'] = (@res.now + 10).httpdate
      @res.should.not.be.stale
    end
    it 'is true when the TTL is >= 0' do
      @res.headers['Expires'] = (@res.now - 10).httpdate
      @res.should.be.stale
    end
  end

  describe '#ttl' do
    it 'is nil when no Expires or Cache-Control headers present' do
      @res.ttl.should.be.nil
    end
    it 'uses the Expires header when no max-age is present' do
      @res.headers['Expires'] = (@res.now + (60**2)).httpdate
      @res.ttl.should.be.close(60**2, 1)
    end
    it 'returns negative values when Expires is in part' do
      @res.ttl.should.be.nil
      @res.headers['Expires'] = @one_hour_ago.httpdate
      @res.ttl.should.be < 0
    end
    it 'uses the Cache-Control max-age value when present' do
      @res.headers['Cache-Control'] = 'max-age=60'
      @res.ttl.should.be.close(60, 1)
    end
  end

  describe '#vary' do
    it 'is nil when no Vary header is present' do
      @res.vary.should.be.nil
    end
    it 'returns the literal value of the Vary header' do
      @res.headers['Vary'] = 'Foo Bar Baz'
      @res.vary.should.equal 'Foo Bar Baz'
    end
    it 'can be checked for existence using the #vary? method' do
      @res.should.respond_to :vary?
      @res.should.not.vary
      @res.headers['Vary'] = '*'
      @res.should.vary
    end
  end

  describe '#vary_header_names' do
    it 'returns an empty Array when no Vary header is present' do
      @res.vary_header_names.should.be.empty
    end
    it 'parses a single header name value' do
      @res.headers['Vary'] = 'Accept-Language'
      @res.vary_header_names.should.equal ['Accept-Language']
    end
    it 'parses multiple header name values separated by spaces' do
      @res.headers['Vary'] = 'Accept-Language User-Agent    X-Foo'
      @res.vary_header_names.should.equal \
        ['Accept-Language', 'User-Agent', 'X-Foo']
    end
    it 'parses multiple header name values separated by commas' do
      @res.headers['Vary'] = 'Accept-Language,User-Agent,    X-Foo'
      @res.vary_header_names.should.equal \
        ['Accept-Language', 'User-Agent', 'X-Foo']
    end
  end
end
