local constants = require "kong.constants"
local plugin_handler = require "kong.plugins.escher.handler"

describe("wsse plugin", function()
    local old_ngx = _G.ngx
    local mock_config= {
        anonymous = 'anonym123',
        timeframe_validation_treshhold_in_minutes = 5
    }
    local handler

    local anonymous_consumer = {
        id = 'anonym123',
        custom_id = '',
        username = 'anonymous'
    }

    local test_consumer = {
        id = 'test123',
        custom_id = '',
        username = 'test'
    }

    before_each(function()
        local ngx_req_headers = {}
        local stubbed_ngx = {
            req = {
                get_headers = function()
                    return ngx_req_headers
                end,
                set_header = function(header_name, header_value)
                    ngx_req_headers[header_name] = header_value
                end
            },
            ctx = {},
            header = {},
            log = function(...) end,
            say = function(...) end,
            exit = function(...) end,
            var = {
                request_id = 123
            }
        }

        _G.ngx = stubbed_ngx
        stub(stubbed_ngx, "say")
        stub(stubbed_ngx, "exit")
        stub(stubbed_ngx, "log")

        handler = plugin_handler()
    end)

    describe("#access", function()

        it("set anonymous header to true when request not has x-ems-auth header", function()
            handler:access(mock_config)
            assert.are.equal(true, ngx.req.get_headers()[constants.HEADERS.ANONYMOUS])
        end)


    end)

end)