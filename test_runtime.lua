-- test_runtime.lua — Pure Lua unit tests for chi_runtime.lua
-- Requires: luajit (no JVM, no chi compiler)
-- Usage: luajit test_runtime.lua

local pass, fail = 0, 0

local function assert_eq(actual, expected, msg)
    if actual == expected then
        pass = pass + 1
    else
        fail = fail + 1
        io.write("FAIL: " .. msg .. "\n")
        io.write("  expected: " .. tostring(expected) .. "\n")
        io.write("  actual:   " .. tostring(actual) .. "\n")
    end
end

local function assert_true(value, msg)
    assert_eq(value, true, msg)
end

local function assert_false(value, msg)
    assert_eq(value, false, msg)
end

local function assert_match(actual, pattern, msg)
    if type(actual) == "string" and actual:match(pattern) then
        pass = pass + 1
    else
        fail = fail + 1
        io.write("FAIL: " .. msg .. "\n")
        io.write("  expected match: " .. pattern .. "\n")
        io.write("  actual:         " .. tostring(actual) .. "\n")
    end
end

-- Locate runtime files relative to this script
local script_dir = arg[0]:match("(.*/)") or "./"
local base_dir = script_dir .. "../compiler/src/main/resources/"

-- Load UTF-8 support
utf8 = dofile(base_dir .. "utf8.lua")

-- Load chistr
chistr = dofile(base_dir .. "chistr.lua")

-- Load the runtime under test
dofile(base_dir .. "chi_runtime.lua")

io.write("Testing chi_runtime.lua\n")
io.write(string.rep("-", 40) .. "\n")

---------------------------------------------------------------------------
-- chi_new_string
---------------------------------------------------------------------------
assert_eq(chi_new_string(42), "42", "chi_new_string(42) -> '42'")
assert_eq(chi_new_string("hello"), "hello", "chi_new_string('hello') -> 'hello'")
assert_eq(chi_new_string(true), "true", "chi_new_string(true) -> 'true'")

---------------------------------------------------------------------------
-- chi_tostring
---------------------------------------------------------------------------
assert_eq(chi_tostring(42), "42", "chi_tostring(42)")
assert_eq(chi_tostring(3.14), "3.14", "chi_tostring(3.14)")
assert_eq(chi_tostring(true), "true", "chi_tostring(true)")
assert_eq(chi_tostring(false), "false", "chi_tostring(false)")
assert_eq(chi_tostring("hello"), "hello", "chi_tostring('hello')")
assert_eq(chi_tostring(nil), "unit", "chi_tostring(nil) -> 'unit'")
assert_eq(chi_tostring(function() end), "<function>", "chi_tostring(function) -> '<function>'")

---------------------------------------------------------------------------
-- chi_is_int
---------------------------------------------------------------------------
assert_true(chi_is_int(42), "chi_is_int(42)")
assert_true(chi_is_int(0), "chi_is_int(0)")
assert_true(chi_is_int(-7), "chi_is_int(-7)")
assert_false(chi_is_int(3.14), "chi_is_int(3.14) -> false")
assert_false(chi_is_int(0.1), "chi_is_int(0.1) -> false")
assert_false(chi_is_int("42"), "chi_is_int('42') -> false")
assert_false(chi_is_int(nil), "chi_is_int(nil) -> false")

---------------------------------------------------------------------------
-- chi_is_float
---------------------------------------------------------------------------
assert_true(chi_is_float(3.14), "chi_is_float(3.14)")
assert_true(chi_is_float(0.1), "chi_is_float(0.1)")
assert_true(chi_is_float(-2.5), "chi_is_float(-2.5)")
assert_false(chi_is_float(42), "chi_is_float(42) -> false")
assert_false(chi_is_float(0), "chi_is_float(0) -> false")
assert_false(chi_is_float("3.14"), "chi_is_float('3.14') -> false")
assert_false(chi_is_float(nil), "chi_is_float(nil) -> false")

---------------------------------------------------------------------------
-- chi_is_array
---------------------------------------------------------------------------
local arr = chi_new_array(1, 2, 3)
assert_true(chi_is_array(arr), "chi_is_array(chi_new_array(1,2,3))")
assert_false(chi_is_array({}), "chi_is_array({}) -> false (plain table)")
assert_false(chi_is_array("hello"), "chi_is_array('hello') -> false")
assert_false(chi_is_array(42), "chi_is_array(42) -> false")

---------------------------------------------------------------------------
-- chi_is_record
---------------------------------------------------------------------------
local rec = setmetatable({name = "Chi", version = 1}, record_meta_table)
assert_true(chi_is_record(rec), "chi_is_record(record)")
assert_false(chi_is_record({}), "chi_is_record({}) -> false (plain table)")
assert_false(chi_is_record(arr), "chi_is_record(array) -> false")
assert_false(chi_is_record("hello"), "chi_is_record('hello') -> false")

---------------------------------------------------------------------------
-- chi_new_array
---------------------------------------------------------------------------
local a0 = chi_new_array()
assert_eq(#a0, 0, "chi_new_array() has length 0")
assert_true(chi_is_array(a0), "chi_new_array() is an array")

local a3 = chi_new_array(10, 20, 30)
assert_eq(#a3, 3, "chi_new_array(10,20,30) has length 3")
assert_eq(a3[1], 10, "array[1] == 10")
assert_eq(a3[2], 20, "array[2] == 20")
assert_eq(a3[3], 30, "array[3] == 30")

---------------------------------------------------------------------------
-- array_meta_table __tostring
---------------------------------------------------------------------------
assert_eq(tostring(chi_new_array(1, 2, 3)), "[1, 2, 3]", "tostring(array) -> '[1, 2, 3]'")
assert_eq(tostring(chi_new_array()), "[]", "tostring(empty array) -> '[]'")
assert_eq(tostring(chi_new_array("a", "b")), "[a, b]", "tostring(string array)")

---------------------------------------------------------------------------
-- record_meta_table __tostring
---------------------------------------------------------------------------
local rec1 = setmetatable({x = 1}, record_meta_table)
assert_match(tostring(rec1), "x: 1", "tostring(record {x=1}) contains 'x: 1'")

---------------------------------------------------------------------------
-- chi_record_pairs
---------------------------------------------------------------------------
local rec2 = setmetatable({a = 1, b = 2}, record_meta_table)
local keys = {}
for k, v in chi_record_pairs(rec2) do
    keys[k] = v
end
assert_eq(keys["a"], 1, "chi_record_pairs yields a=1")
assert_eq(keys["b"], 2, "chi_record_pairs yields b=2")

---------------------------------------------------------------------------
-- chi_handle_effect — basic (no effects fired)
---------------------------------------------------------------------------
local co = coroutine.create(function()
    return 42
end)
local result = chi_handle_effect(co, nil, {})
assert_eq(result, 42, "chi_handle_effect: simple coroutine returns 42")

---------------------------------------------------------------------------
-- chi_handle_effect — single effect
---------------------------------------------------------------------------
local co2 = coroutine.create(function()
    local val = coroutine.yield("get_value", {})
    return val * 2
end)
local handlers2 = {
    get_value = function(args)
        return 21
    end
}
local result2 = chi_handle_effect(co2, nil, handlers2)
assert_eq(result2, 42, "chi_handle_effect: handler returns 21, body doubles to 42")

---------------------------------------------------------------------------
-- chi_handle_effect — multiple yields
---------------------------------------------------------------------------
local co3 = coroutine.create(function()
    local a = coroutine.yield("ask", {"first"})
    local b = coroutine.yield("ask", {"second"})
    return a .. "+" .. b
end)
local handlers3 = {
    ask = function(args)
        return "got_" .. args[1]
    end
}
local result3 = chi_handle_effect(co3, nil, handlers3)
assert_eq(result3, "got_first+got_second", "chi_handle_effect: multiple yields")

---------------------------------------------------------------------------
-- chi_decode_type — primitives
---------------------------------------------------------------------------
local t_int = chi_decode_type('{tag="int"}')
assert_eq(t_int.tag, "int", "chi_decode_type: int")

local t_string = chi_decode_type('{tag="string"}')
assert_eq(t_string.tag, "string", "chi_decode_type: string")

local t_bool = chi_decode_type('{tag="bool"}')
assert_eq(t_bool.tag, "bool", "chi_decode_type: bool")

---------------------------------------------------------------------------
-- chi_decode_type — function type
---------------------------------------------------------------------------
local t_fn = chi_decode_type('{tag="fn",types={{tag="int"},{tag="string"}},typeParams={},defaults=0}')
assert_eq(t_fn.tag, "fn", "chi_decode_type: fn tag")
assert_eq(#t_fn.types, 2, "chi_decode_type: fn has 2 types")
assert_eq(t_fn.types[1].tag, "int", "chi_decode_type: fn param is int")
assert_eq(t_fn.types[2].tag, "string", "chi_decode_type: fn return is string")
assert_eq(t_fn.defaults, 0, "chi_decode_type: fn defaults=0")

---------------------------------------------------------------------------
-- chi_decode_type — array type
---------------------------------------------------------------------------
local t_arr = chi_decode_type('{tag="array",elem={tag="int"},typeIds={{"std","lang","array"}}}')
assert_eq(t_arr.tag, "array", "chi_decode_type: array tag")
assert_eq(t_arr.elem.tag, "int", "chi_decode_type: array elem is int")

---------------------------------------------------------------------------
-- chi_decode_type — record type
---------------------------------------------------------------------------
local t_rec = chi_decode_type('{tag="record",fields={{"name",{tag="string"}},{"age",{tag="int"}}},id={"m","p","Foo"},typeIds={{"m","p","Foo"}},typeParams={}}')
assert_eq(t_rec.tag, "record", "chi_decode_type: record tag")
assert_eq(#t_rec.fields, 2, "chi_decode_type: record has 2 fields")
assert_eq(t_rec.fields[1][1], "name", "chi_decode_type: record field 'name'")
assert_eq(t_rec.fields[1][2].tag, "string", "chi_decode_type: record field type 'string'")

---------------------------------------------------------------------------
-- Bootstrap packages — std/lang exists and has expected symbols
---------------------------------------------------------------------------
local std_lang = package.loaded['std/lang']
assert_true(std_lang ~= nil, "std/lang is loaded")
assert_true(std_lang._package.println ~= nil, "std/lang._package.println exists")
assert_true(std_lang._package.print ~= nil, "std/lang._package.print exists")
assert_true(std_lang._package.compileLua ~= nil, "std/lang._package.compileLua exists")
assert_true(std_lang._package.eval ~= nil, "std/lang._package.eval exists")
assert_true(std_lang._package.reload ~= nil, "std/lang._package.reload exists")
assert_true(std_lang._package.loadModule ~= nil, "std/lang._package.loadModule exists")
assert_eq(std_lang._package.println.public, true, "std/lang println is public")

---------------------------------------------------------------------------
-- Bootstrap packages — std/lang.any
---------------------------------------------------------------------------
local std_lang_any = package.loaded['std/lang.any']
assert_true(std_lang_any ~= nil, "std/lang.any is loaded")
assert_true(std_lang_any._package.toString ~= nil, "std/lang.any._package.toString exists")
assert_eq(std_lang_any.toString(42), "42", "std/lang.any.toString(42) works")

---------------------------------------------------------------------------
-- Bootstrap packages — user/default
---------------------------------------------------------------------------
local user_default = package.loaded['user/default']
assert_true(user_default ~= nil, "user/default is loaded")
assert_true(user_default._package ~= nil, "user/default._package exists")

---------------------------------------------------------------------------
-- chi_compile stub in standalone mode
---------------------------------------------------------------------------
local ok, err = pcall(chi_compile)
assert_false(ok, "chi_compile errors in standalone mode")
assert_match(err, "standalone", "chi_compile error mentions 'standalone'")

---------------------------------------------------------------------------
-- Type strings in bootstrap packages are valid Lua literals
---------------------------------------------------------------------------
local println_type = chi_decode_type(std_lang._package.println.type)
assert_eq(println_type.tag, "fn", "println type decodes to fn")

local toString_type = chi_decode_type(std_lang_any._package.toString.type)
assert_eq(toString_type.tag, "fn", "toString type decodes to fn")

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
io.write(string.rep("-", 40) .. "\n")
if fail == 0 then
    io.write(string.format("\27[32m%d passed\27[0m  (luajit: chi_runtime.lua)\n", pass))
else
    io.write(string.format("\27[32m%d passed\27[0m, \27[31m%d failed\27[0m  (luajit: chi_runtime.lua)\n", pass, fail))
end
os.exit(fail > 0 and 1 or 0)
