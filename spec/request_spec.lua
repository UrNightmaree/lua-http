describe("http.request module", function()
	local request = require "http.request"
	it("can construct a request from a uri", function()
		do -- http url; no path
			local req = request.new_from_uri("http://example.com")
			assert.same("example.com", req.host)
			assert.same(80, req.port)
			assert.falsy(req.tls)
			assert.same("example.com", req.headers:get ":authority")
			assert.same("GET", req.headers:get ":method")
			assert.same("/", req.headers:get ":path")
			assert.same("http", req.headers:get ":scheme")
			assert.same(nil, req.body)
		end
		do -- https
			local req = request.new_from_uri("https://example.com/path?query")
			assert.same("example.com", req.host)
			assert.same(443, req.port)
			assert.truthy(req.tls)
			assert.same("example.com", req.headers:get ":authority")
			assert.same("GET", req.headers:get ":method")
			assert.same("/path?query", req.headers:get ":path")
			assert.same("https", req.headers:get ":scheme")
			assert.same(nil, req.body)
		end
		do -- with userinfo section
			local basexx = require "basexx"
			local req = request.new_from_uri("https://user:password@example.com/")
			assert.same("example.com", req.host)
			assert.same(443, req.port)
			assert.truthy(req.tls)
			assert.same("example.com", req.headers:get ":authority")
			assert.same("GET", req.headers:get ":method")
			assert.same("/", req.headers:get ":path")
			assert.same("https", req.headers:get ":scheme")
			assert.same("user:password", basexx.from_base64(req.headers:get "authorization":match "^basic%s+(.*)"))
			assert.same(nil, req.body)
		end
	end)
	it("can construct a CONNECT request", function()
		do -- http url; no path
			local req = request.new_connect("http://example.com", "connect.me")
			assert.same("example.com", req.host)
			assert.same(80, req.port)
			assert.falsy(req.tls)
			assert.same("connect.me", req.headers:get ":authority")
			assert.same("CONNECT", req.headers:get ":method")
			assert.falsy(req.headers:has ":path")
			assert.falsy(req.headers:has ":scheme")
			assert.same(nil, req.body)
		end
		do -- https
			local req = request.new_connect("https://example.com", "connect.me:1234")
			assert.same("example.com", req.host)
			assert.same(443, req.port)
			assert.truthy(req.tls)
			assert.same("connect.me:1234", req.headers:get ":authority")
			assert.same("CONNECT", req.headers:get ":method")
			assert.falsy(req.headers:has ":path")
			assert.falsy(req.headers:has ":scheme")
			assert.same(nil, req.body)
		end
		do -- with userinfo section
			local basexx = require "basexx"
			local req = request.new_connect("https://user:password@example.com", "connect.me")
			assert.same("example.com", req.host)
			assert.same(443, req.port)
			assert.truthy(req.tls)
			assert.same("connect.me", req.headers:get ":authority")
			assert.same("CONNECT", req.headers:get ":method")
			assert.falsy(req.headers:has ":path")
			assert.falsy(req.headers:has ":scheme")
			assert.same("user:password", basexx.from_base64(req.headers:get "proxy-authorization":match "^basic%s+(.*)"))
			assert.same(nil, req.body)
		end
		do -- anything with a path should fail
			assert.has.errors(function() request.new_connect("http://example.com/") end)
			assert.has.errors(function() request.new_connect("http://example.com/path") end)
		end
	end)
	it("fails on invalid URIs", function()
		assert.has.errors(function() request.new_from_uri("not a URI") end)

		-- no scheme
		assert.has.errors(function() request.new_from_uri("example.com") end)

		-- trailing junk
		assert.has.errors(function() request.new_from_uri("example.com/foo junk.") end)
	end)
	it("can (sometimes) roundtrip via :to_url()", function()
		local function test(uri)
			local req = request.new_from_uri(uri)
			assert.same(uri, req:to_url())
		end
		test("http://example.com/")
		test("https://example.com/")
		test("https://example.com:1234/")
		test("http://foo:bar@example.com:1234/path?query")
		test("https://fo%20o:ba%20r@example.com:1234/path%20spaces")
	end)
	it(":to_url() throws on un-coerable authorization", function()
		local req = request.new_from_uri("http://example.com/")
		req.headers:upsert("authorization", "can't go in a uri")
		assert.has.errors(function()
			req:to_url()
		end)
	end)
	it("handles CONNECT requests in :to_url()", function()
		local function test(uri)
			local req = request.new_connect(uri, "connect.me")
			assert.same(uri, req:to_url())
		end
		test("http://example.com")
		test("https://example.com")
		test("https://example.com:1234")
		test("https://foo:bar@example.com:1234")
		assert.has.errors(function() test("https://example.com/path") end)
	end)
	it(":set_body sets content-length for string arguments", function()
		local req = request.new_from_uri("http://example.com")
		assert.falsy(req.headers:has("content-length"))
		local str = "a string"
		req:set_body(str)
		assert.same(string.format("%d", #str), req.headers:get("content-length"))
	end)
	it(":set_body sets expect 100-continue for file arguments", function()
		local req = request.new_from_uri("http://example.com")
		assert.falsy(req.headers:has("expect"))
		req:set_body(io.tmpfile())
		assert.same("100-continue", req.headers:get("expect"))
	end)
	local headers = require "http.headers"
	it(":handle_redirect works", function()
		local orig_req = request.new_from_uri("http://example.com")
		local orig_headers = headers.new()
		orig_headers:append(":status", "301")
		orig_headers:append("location", "/foo")
		local new_req = orig_req:handle_redirect(orig_headers)
		-- same
		assert.same(orig_req.host, new_req.host)
		assert.same(orig_req.port, new_req.port)
		assert.same(orig_req.tls, new_req.tls)
		assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
		assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
		assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
		assert.same(orig_req.body, new_req.body)
		-- different
		assert.same("/foo", new_req.headers:get ":path")
		assert.same(orig_req.max_redirects-1, new_req.max_redirects)
	end)
	it(":handle_redirect works with cross-scheme port-less uri", function()
		local orig_req = request.new_from_uri("http://example.com")
		local orig_headers = headers.new()
		orig_headers:append(":status", "302")
		orig_headers:append("location", "https://blah.com/example")
		local new_req = orig_req:handle_redirect(orig_headers)
		-- same
		assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
		assert.same(orig_req.body, new_req.body)
		-- different
		assert.same(false, orig_req.tls)
		assert.same(true, new_req.tls)
		assert.same("https", new_req.headers:get ":scheme")
		assert.same("blah.com", new_req.host)
		assert.same(80, orig_req.port)
		assert.same(443, new_req.port)
		assert.same("blah.com", new_req.headers:get ":authority")
		assert.same("/example", new_req.headers:get ":path")
		assert.same(orig_req.max_redirects-1, new_req.max_redirects)
	end)
	it(":handle_redirect works with scheme relative uri", function()
		local orig_req = request.new_from_uri("http://example.com")
		local orig_headers = headers.new()
		orig_headers:append(":status", "302")
		orig_headers:append("location", "//blah.com:1234/example")
		local new_req = orig_req:handle_redirect(orig_headers)
		-- same
		assert.same(orig_req.tls, new_req.tls)
		assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
		assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
		assert.same(orig_req.body, new_req.body)
		-- different
		assert.same("blah.com", new_req.host)
		assert.same(1234, new_req.port)
		assert.same("blah.com:1234", new_req.headers:get ":authority")
		assert.same("/example", new_req.headers:get ":path")
		assert.same(orig_req.max_redirects-1, new_req.max_redirects)
	end)
	it(":handle_redirect detects maximum redirects exceeded", function()
		local ce = require "cqueues.errno"
		local orig_req = request.new_from_uri("http://example.com")
		orig_req.max_redirects = 0
		local orig_headers = headers.new()
		orig_headers:append(":status", "302")
		orig_headers:append("location", "/")
		assert.same({nil, "maximum redirects exceeded", ce.ELOOP}, {orig_req:handle_redirect(orig_headers)})
	end)
	it(":handle_redirect detects missing location header", function()
		local ce = require "cqueues.errno"
		local orig_req = request.new_from_uri("http://example.com")
		local orig_headers = headers.new()
		orig_headers:append(":status", "302")
		assert.same({nil, "missing location header for redirect", ce.EINVAL}, {orig_req:handle_redirect(orig_headers)})
	end)
	it(":handle_redirect detects POST => GET transformation", function()
		local orig_req = request.new_from_uri("http://example.com")
		orig_req.headers:upsert(":method", "POST")
		orig_req.headers:upsert("content-type", "text/plain")
		orig_req:set_body("foo")
		local orig_headers = headers.new()
		orig_headers:append(":status", "303")
		orig_headers:append("location", "/foo")
		local new_req = orig_req:handle_redirect(orig_headers)
		-- same
		assert.same(orig_req.host, new_req.host)
		assert.same(orig_req.port, new_req.port)
		assert.same(orig_req.tls, new_req.tls)
		assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
		assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
		-- different
		assert.same("GET", new_req.headers:get ":method")
		assert.same("/foo", new_req.headers:get ":path")
		assert.falsy(new_req.headers:has "content-type")
		assert.same(nil, new_req.body)
		assert.same(orig_req.max_redirects-1, new_req.max_redirects)
	end)
	it(":handle_redirect deletes keeps original custom host, port and sendname if relative", function()
		local orig_req = request.new_from_uri("http://example.com")
		orig_req.host = "other.com"
		orig_req.sendname = "something.else"
		local orig_headers = headers.new()
		orig_headers:append(":status", "301")
		orig_headers:append("location", "/foo")
		local new_req = orig_req:handle_redirect(orig_headers)
		-- same
		assert.same(orig_req.host, new_req.host)
		assert.same(orig_req.port, new_req.port)
		assert.same(orig_req.tls, new_req.tls)
		assert.same(orig_req.sendname, new_req.sendname)
		assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
		assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
		assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
		assert.same(orig_req.body, new_req.body)
		-- different
		assert.same("/foo", new_req.headers:get ":path")
		assert.same(orig_req.max_redirects-1, new_req.max_redirects)
	end)
end)
