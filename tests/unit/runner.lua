-- Minimal deterministic Lua test runner for BH pure modules.
-- The runner is intentionally dependency-free so it can execute in Kahlua,
-- Lua 5.1, LuaJIT or the Node/fengari harness used by tools/run_tests.mjs.

BH_TEST = BH_TEST or {}
BH_TEST.tests = BH_TEST.tests or {}
BH_TEST.failures = BH_TEST.failures or {}
BH_TEST.assertions = BH_TEST.assertions or 0
BH_TEST.prefix = ""

local function fail(message)
    error(tostring(message), 3)
end

function describe(name, callback)
    local previous = BH_TEST.prefix
    BH_TEST.prefix = previous == "" and tostring(name) or (previous .. " / " .. tostring(name))
    local ok, errorMessage = pcall(callback)
    BH_TEST.prefix = previous
    if not ok then
        fail("describe failed: " .. tostring(errorMessage))
    end
end

function it(name, callback)
    BH_TEST.tests[#BH_TEST.tests + 1] = {
        name = BH_TEST.prefix == "" and tostring(name) or (BH_TEST.prefix .. " / " .. tostring(name)),
        callback = callback,
    }
end

function eq(actual, expected, message)
    BH_TEST.assertions = BH_TEST.assertions + 1
    if actual ~= expected then
        fail(string.format("%s: expected %s, got %s", message or "equality", tostring(expected), tostring(actual)))
    end
end

function ne(actual, expected, message)
    BH_TEST.assertions = BH_TEST.assertions + 1
    if actual == expected then
        fail(string.format("%s: did not expect %s", message or "inequality", tostring(expected)))
    end
end

function truthy(value, message)
    BH_TEST.assertions = BH_TEST.assertions + 1
    if not value then
        fail(message or "expected truthy value")
    end
end

function falsy(value, message)
    BH_TEST.assertions = BH_TEST.assertions + 1
    if value then
        fail(message or "expected falsy value")
    end
end

function approx(actual, expected, tolerance, message)
    BH_TEST.assertions = BH_TEST.assertions + 1
    tolerance = tolerance or 0.001
    if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
        fail(string.format("%s: expected %.4f +/- %.4f, got %s", message or "approx", expected, tolerance, tostring(actual)))
    end
end

function contains(haystack, needle, message)
    BH_TEST.assertions = BH_TEST.assertions + 1
    if type(haystack) ~= "string" or not string.find(haystack, needle, 1, true) then
        fail(string.format("%s: %s does not contain %s", message or "contains", tostring(haystack), tostring(needle)))
    end
end

function deep_eq(actual, expected, message)
    BH_TEST.assertions = BH_TEST.assertions + 1
    local function compare(left, right, path)
        if type(left) ~= type(right) then
            return false, path .. " type"
        end
        if type(left) ~= "table" then
            return left == right, path
        end
        for key, value in pairs(left) do
            local ok, where = compare(value, right[key], path .. "." .. tostring(key))
            if not ok then
                return false, where
            end
        end
        for key in pairs(right) do
            if left[key] == nil then
                return false, path .. "." .. tostring(key)
            end
        end
        return true, path
    end
    local ok, where = compare(actual, expected, "$")
    if not ok then
        fail(string.format("%s at %s", message or "deep equality", where))
    end
end

function BH_TEST_RUN()
    local passed = 0
    for index = 1, #BH_TEST.tests do
        local test = BH_TEST.tests[index]
        local ok, errorMessage = pcall(test.callback)
        if ok then
            passed = passed + 1
            print("PASS " .. test.name)
        else
            BH_TEST.failures[#BH_TEST.failures + 1] = {
                name = test.name,
                error = tostring(errorMessage),
            }
            print("FAIL " .. test.name .. " :: " .. tostring(errorMessage))
        end
    end

    print(string.format(
        "TEST_SUMMARY total=%d passed=%d failed=%d assertions=%d",
        #BH_TEST.tests,
        passed,
        #BH_TEST.failures,
        BH_TEST.assertions
    ))
    return #BH_TEST.failures == 0
end
