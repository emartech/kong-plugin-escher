local helpers = require "spec.helpers"
local cjson = require "cjson"
local Escher = require "escher"
local TestHelper = require "spec.test_helper"

local function get_response_body(response)
    local body = assert.res_status(201, response)
    return cjson.decode(body)
end

local function setup_test_env()
    helpers.dao:truncate_tables()

    local service = get_response_body(TestHelper.setup_service())
    local route = get_response_body(TestHelper.setup_route_for_service(service.id))
    local plugin = get_response_body(TestHelper.setup_plugin_for_service(service.id, 'escher', { encryption_key_path = "/secret.txt" }))
    local consumer = get_response_body(TestHelper.setup_consumer('test'))

    return service, route, plugin, consumer
end

describe("Plugin: escher (access) #e2e", function()

    setup(function()
        helpers.start_kong({ custom_plugins = 'escher' })
    end)

    teardown(function()
        helpers.stop_kong(nil)
    end)

    describe("Admin API", function()

        local service, route, plugin, consumer

        before_each(function()
            service, route, plugin, consumer = setup_test_env()
        end)

        it("registered the plugin globally", function()
            local res = assert(helpers.admin_client():send {
                method = "GET",
                path = "/plugins/" .. plugin.id,
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.is_table(json)
            assert.is_not.falsy(json.enabled)
        end)

        it("registered the plugin for the api", function()
            local res = assert(helpers.admin_client():send {
                method = "GET",
                path = "/plugins/" ..plugin.id,
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.is_equal(api_id, json.api_id)
        end)

        it("should create a new escher key for the given consumer", function()
          local res = assert(helpers.admin_client():send {
              method = "POST",
              path = "/consumers/" .. consumer.id .. "/escher_key/",
              body = {
                key = 'test_key',
                secret = 'test_secret'
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.is_equal('test_key', json.key)
        end)

        it("should create a new escher key with encrypted secret using encryption key from file", function()
            local ecrypto = TestHelper.get_easy_crypto()

            local secret = 'test_secret'
            local res = assert(helpers.admin_client():send {
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/escher_key/",
                body = {
                  key = 'test_key_v2',
                  secret = secret
                },
                headers = {
                  ["Content-Type"] = "application/json"
                }
            })

            local body = assert.res_status(201, res)
            local json = cjson.decode(body)

            assert.is_equal('test_key_v2', json.key)
            assert.are_not.equals(secret, json.secret)

            local encryption_key = TestHelper.load_encryption_key_from_file(plugin.config.encryption_key_path)

            assert.is_equal(secret, ecrypto:decrypt(encryption_key, json.secret))
        end)

        it("should be able to retrieve an escher key", function()
            local create_call = assert(helpers.admin_client():send {
              method = "POST",
              path = "/consumers/" .. consumer.id .. "/escher_key/",
              body = {
                key = 'another_test_key',
                secret = 'test_secret'
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(201, create_call)

            local retrieve_call = assert(helpers.admin_client():send {
                method = "GET",
                path = "/consumers/" .. consumer.id .. "/escher_key/another_test_key"
              })

            local body = assert.res_status(200, retrieve_call)
            local json = cjson.decode(body)
            assert.is_equal('another_test_key', json.key)
            assert.is_equal(nil, json.secret)
        end)

        it("should be able to delete an escher key", function()
            local create_call = assert(helpers.admin_client():send {
              method = "POST",
              path = "/consumers/" .. consumer.id .. "/escher_key/",
              body = {
                key = 'yet_another_test_key',
                secret = 'test_secret'
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(201, create_call)

            local delete_call = assert(helpers.admin_client():send {
                method = "DELETE",
                path = "/consumers/" .. consumer.id .. "/escher_key/yet_another_test_key"
              })

            assert.res_status(204, delete_call)
          end)
    end)

    describe("Plugin setup", function()
        local service, route, plugin, consumer

        before_each(function()
            helpers.dao:truncate_tables()
            service = get_response_body(TestHelper.setup_service())
            route = get_response_body(TestHelper.setup_route_for_service(service.id))
        end)

        context("when using a wrong config", function()
            it("should respond 400 when encryption file does not exists", function()
                local res = TestHelper.setup_plugin_for_service(service.id, 'escher', { encryption_key_path = "/kong.txt" })

                assert.res_status(400, res)
            end)

            it("should respond 400 when encryption file path does not equal with the other escher plugin configurations", function()
                local other_service = get_response_body(TestHelper.setup_service("second"))

                get_response_body(TestHelper.setup_route_for_service(other_service.id))

                local f = io.open("/tmp/other_secret.txt", "w")
                f:close()

                TestHelper.setup_plugin_for_service(service.id, 'escher', { encryption_key_path = "/secret.txt" })
                local second_res = TestHelper.setup_plugin_for_service(other_service.id, 'escher', { encryption_key_path = "/tmp/other_secret.txt" })

                assert.res_status(400, second_res)
            end)

            it("should indicate failure when message_template is not a valid JSON", function()
                local plugin_response = TestHelper.setup_plugin_for_service(service.id, "escher", {
                    message_template = "not a JSON"
                })

                local body = assert.res_status(400, plugin_response)
                local plugin = cjson.decode(body)

                assert.is_equal("message_template should be valid JSON object", plugin["config.message_template"])
            end)

            it("should indicate failure when status code is not in the HTTP status range", function()
                local plugin_response = TestHelper.setup_plugin_for_service(service.id, "escher", {
                    status_code = 600
                })

                local body = assert.res_status(400, plugin_response)
                local plugin = cjson.decode(body)

                assert.is_equal("status code is invalid", plugin["config.status_code"])
            end)
        end)

        it("should use dafaults configs aren't provided", function()
            local plugin_response = TestHelper.setup_plugin_for_service(service.id, "escher", {})

            local body = assert.res_status(201, plugin_response)
            local plugin = cjson.decode(body)

            assert.is_equal('{"message": "%s"}', plugin.config.message_template)
            assert.is_equal(401, plugin.config.status_code)
        end)
    end)

    describe("Authentication", function()

        local service, route, plugin, consumer

        before_each(function()
            service, route, plugin, consumer = setup_test_env()
        end)

        local current_date = os.date("!%Y%m%dT%H%M%SZ")

        local config = {
            algoPrefix      = 'EMS',
            vendorKey       = 'EMS',
            credentialScope = 'eu/suite/ems_request',
            authHeaderName  = 'X-Ems-Auth',
            dateHeaderName  = 'X-Ems-Date',
            accessKeyId     = 'test_key',
            apiSecret       = 'test_secret',
            date            = current_date,
        }

        local config_wrong_api_key = {
            algoPrefix      = 'EMS',
            vendorKey       = 'EMS',
            credentialScope = 'eu/suite/ems_request',
            authHeaderName  = 'X-Ems-Auth',
            dateHeaderName  = 'X-Ems-Date',
            accessKeyId     = 'wrong_key',
            apiSecret       = 'test_secret',
            date            = current_date,
        }

        local request_headers = {
            { "X-Ems-Date", current_date },
            { "Host", "test1.com" }
        }

        local request = {
            ["method"] = "GET",
            ["headers"] = request_headers,
            --["body"] = '',
            ["url"] = "/request"
        }

        local escher = Escher:new(config)
        local escher_wrong_api_key = Escher:new(config_wrong_api_key)

        local ems_auth_header = escher:generateHeader(request, {})
        local ems_auth_header_wrong_api_key = escher_wrong_api_key:generateHeader(request, {})

        context("when anonymous user does not allowed", function()
            it("responds with status 401 if request not has X-EMS-DATE and X-EMS-AUTH header", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["Host"] = "test1.com"
                    }
                })

                local body = assert.res_status(401, res)
                assert.is_equal('{"message":"The x-ems-date header is missing"}', body)
            end)

            it("responds with status 401 when X-EMS-AUTH header is invalid", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = 'invalid header'
                    }
                })

                local body = assert.res_status(401, res)
                assert.is_equal('{"message":"Could not parse X-Ems-Auth header"}', body)
            end)

            it("responds with status 401 when X-EMS-Date header is invalid", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = 'invalid date',
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = 'invalid header'
                    }
                })

                local body = assert.res_status(401, res)
                assert.is_equal('{"message":"Could not parse X-Ems-Date header"}', body)
            end)

            it("responds with status 200 when X-EMS-AUTH header is valid", function()
                assert(helpers.admin_client():send {
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key/",
                    body = {
                        key = 'test_key',
                        secret = 'test_secret'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header
                    }
                })

                assert.res_status(200, res)
            end)

            it("responds with status 401 when api key was not found", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header_wrong_api_key
                    }
                })

                local body = assert.res_status(401, res)
                assert.is_equal('{"message":"Invalid Escher key"}', body)
            end)
        end)

        context("when anonymous user allowed", function()
            local service, route, anonymous, plugin, consumer

            before_each(function()
                helpers.dao:truncate_tables()

                service = get_response_body(TestHelper.setup_service())
                route = get_response_body(TestHelper.setup_route_for_service(service.id))

                anonymous = get_response_body(TestHelper.setup_consumer('anonymous'))
                plugin = get_response_body(TestHelper.setup_plugin_for_service(service.id, 'escher', {anonymous = anonymous.id, encryption_key_path = "/secret.txt"}))

                consumer = get_response_body(TestHelper.setup_consumer('TestUser'))
            end)

            it("responds with status 200 if request not has X-EMS-AUTH header", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["Host"] = "test1.com"
                    }
                })

                assert.res_status(200, res)
            end)

            it("should proxy the request with anonymous when X-EMS-AUTH header is invalid", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = 'invalid header'
                    }
                })

                local response = assert.res_status(200, res)
                local body = cjson.decode(response)
                assert.is_equal("anonymous", body.headers["x-consumer-username"])
            end)

            it("should proxy the request with proper user when X-EMS-AUTH header is valid", function()
                assert(helpers.admin_client():send {
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key/",
                    body = {
                        key = 'test_key',
                        secret = 'test_secret'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header
                    }
                })

                local response = assert.res_status(200, res)
                local body = cjson.decode(response)
                assert.is_equal("TestUser", body.headers["x-consumer-username"])
            end)

            it("responds with status 200 when api key was not found", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header_wrong_api_key
                    }
                })

                assert.res_status(200, res)
            end)
        end)

        context("when message template is not default", function()
            local service, route, plugin

            before_each(function()
                helpers.dao:truncate_tables()

                service = get_response_body(TestHelper.setup_service('testservice', 'http://mockbin.org/request'))
                route = get_response_body(TestHelper.setup_route_for_service(service.id, '/'))
                plugin = get_response_body(TestHelper.setup_plugin_for_service(service.id, 'escher', {
                    encryption_key_path = "/secret.txt",
                    message_template = '{"custom-message": "%s"}'
                }))
            end)

            it("should return response message in the given format", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request"
                })

                local response = assert.res_status(401, res)
                local body = cjson.decode(response)

                assert.is_nil(body.message)
                assert.not_nil(body['custom-message'])
                assert.is_equal("The x-ems-date header is missing", body['custom-message'])
            end)

        end)

        context('when given status code for failed authentications', function()
            local service, route, plugin, consumer

            before_each(function()
                helpers.dao:truncate_tables()

                service = get_response_body(TestHelper.setup_service('testservice', 'http://mockbin.org/request'))
                route = get_response_body(TestHelper.setup_route_for_service(service.id, '/'))
                plugin = get_response_body(TestHelper.setup_plugin_for_service(service.id, 'escher', {
                    encryption_key_path = "/secret.txt",
                    status_code = 400
                }))
            end)

            it("should reject request with given HTTP status", function()
                local res = assert(helpers.proxy_client():send {
                    method = "GET",
                    path = "/request"
                })

                assert.res_status(400, res)
            end)

        end)

    end)

end)
