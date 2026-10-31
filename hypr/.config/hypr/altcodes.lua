-- ###############

-- ## ALT CODES ##

-- ###############

-- Windows-style alt codes: hold Alt, type a number on the numpad, release Alt.
--   Alt+133    CP437, the old OEM table (à)
--   Alt+0224   Leading zero: CP1252, the ANSI table (à)
--   Alt+8364   Above 255: the Unicode code point (€), where Windows would just wrap around

local var_insert = "~/.local/bin/clipboard-insert.sh"

local var_cp437 = "☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼"
local var_cp437_high = "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u{A0}"

-- 128-159 are the only codes where CP1252 leaves Latin-1; 0 marks the ones it never assigned
local var_cp1252 = {
    0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
    0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178,
}

local function codepoints(text)
    local points = {}
    for _, point in utf8.codes(text) do
        points[#points + 1] = point
    end
    return points
end

local cp437_low, cp437_high = codepoints(var_cp437), codepoints(var_cp437_high)

local function code_to_char(digits)
    local code = tonumber(digits)
    local point = code
    if code < 256 and digits:sub(1, 1) == "0" then
        if code < 32 then return nil end
        if code >= 128 and code < 160 then point = var_cp1252[code - 127] end
    elseif code < 32 then
        point = cp437_low[code]
    elseif code == 127 then
        point = 0x2302
    elseif code >= 128 and code < 256 then
        point = cp437_high[code - 127]
    end

    if not point or point == 0 or point > 0x10FFFF or (point >= 0xD800 and point <= 0xDFFF) then return nil end
    return utf8.char(point)
end

local var_digits = ""

-- Keycodes rather than keysyms, so the numpad counts with Num Lock off too
local var_numpad = { [90] = 0, [87] = 1, [88] = 2, [89] = 3, [83] = 4, [84] = 5, [85] = 6, [79] = 7, [80] = 8, [81] = 9 }
for keycode, digit in pairs(var_numpad) do
    hl.bind("ALT + code:" .. keycode, function()
        var_digits = var_digits .. digit
    end)
end

local function flush()
    local digits = var_digits
    var_digits = ""
    if digits == "" then return end

    local char = code_to_char(digits)
    if char then
        hl.exec_cmd(var_insert .. " '" .. char:gsub("'", "'\\''") .. "'")
    end
end

-- Not a release bind: Hyprland drops those once another key went down in between, which is every alt code
local var_alt_keys = { [64] = true, [108] = true }
hl.on("input.keyboard.key", function(keycode, _, pressed)
    if var_alt_keys[keycode] and pressed == 0 then flush() end
end)

return { code_to_char = code_to_char }
