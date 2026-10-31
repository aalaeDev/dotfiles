-- Recent screenshots for Walker: the list on the left, the image previewed on the right.
-- Only the dated folders: anything else in there is sorted by hand.
Name = "screenshots"
NamePretty = "Screenshots"
Icon = "camera-photo"
Cache = false
FixedOrder = true

local RECENT = 200
local LIST = [[find "$HOME/Pictures/Screenshots"/20* -maxdepth 1 -type f \( -name '*.png' -o -name '*.gif' \) -printf '%T@ %p\n' 2> /dev/null | sort -rn | cut -d' ' -f2-]]

function GetEntries()
    local entries = {}
    local handle = io.popen(LIST)
    if not handle then
        return entries
    end

    for file in handle:lines() do
        if #entries == RECENT then
            break
        end
        local name = file:match("[^/]+$")
        local extension = name:match("%.(%w+)$")
        local actions = {
            copy = "wl-copy --type image/" .. extension .. " < '" .. file .. "'",
            open = "xdg-open '" .. file .. "'",
            delete = "gio trash '" .. file .. "'",
        }
        if extension == "png" then
            actions.edit = "~/.local/bin/screenshot.sh edit '" .. file .. "'"
        end
        table.insert(entries, {
            Text = (name:gsub("%.%w+$", ""):gsub("_(%d%d)(%d%d)(%d%d)", "  %1:%2:%3")),
            Subtext = extension == "gif" and "GIF" or nil,
            Value = file,
            Actions = actions,
            Preview = file,
            PreviewType = "file",
            Icon = extension == "gif" and "image-gif" or "image-x-generic",
        })
    end
    handle:close()
    return entries
end
