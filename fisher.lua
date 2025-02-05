--[[
Copyright 2014 Seth VanHeulen

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version. 

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]

-- addon information

_addon.name = 'fisher'
_addon.version = '2.8.3'
_addon.command = 'fisher'
_addon.author = 'Seth VanHeulen (Acacia@Odin)'

-- modules

config = require('config')
res = require('resources')
require('lists')
require('pack')
require('strings')

-- default settings

defaults = {}
defaults.chat = 1
defaults.log = -1
defaults.equip = false
defaults.move = false
defaults.delay = {}
defaults.delay.unknown = 25
defaults.delay.release = 1
defaults.delay.cast = 4
defaults.delay.equip = 2
defaults.delay.move = 2
defaults.fatigue = {}
defaults.fatigue.date = os.date('!%Y-%m-%d', os.time() + 32400)
defaults.fatigue.remaining = 200
defaults.fish = {}

settings = config.load('data/%s.xml':format(windower.ffxi.get_player().name), defaults)

-- global variables

bait_id = nil
fish_item_id = nil
fish_bite_id = nil
catch_delay = nil
running = false
log_file = nil
catch_key = nil
last_bite_id = nil
last_item_id = nil
manual = false
cast_count = 0
bite_count = 0
catch_count = 0
error_retry = true

-- debug and logging functions

function message(level, message)
    local prefix = 'E'
    local color = 167
    if level == 1 then
        prefix = 'W'
        color = 200
    elseif level == 2 then
        prefix = 'I'
        color = 207
    elseif level == 3 then
        prefix = 'D'
        color = 160
    end
    if settings.log >= level then
        if log_file == nil then
            log_file = io.open('%sdata/%s.log':format(windower.addon_path, windower.ffxi.get_player().name), 'a')
        end
        if log_file == nil then
            settings.log = -1
            windower.add_to_chat(167, 'unable to open log file')
        else
            log_file:write('%s | %s | %s\n':format(os.date(), prefix, message))
            log_file:flush()
        end
    end
    if settings.chat >= level then
        windower.add_to_chat(color, message)
    end
end

-- bait helper functions

function check_bait()
    local items = windower.ffxi.get_items()
    message(2, 'checking bait')
    if items.equipment.ammo == 0 then
        message(3, 'item slot: 0')
        return false
    elseif items.equipment.ammo_bag == 0 then
        message(3, 'inventory slot: %d, id: %d':format(items.equipment.ammo, items.inventory[items.equipment.ammo].id))
        return items.inventory[items.equipment.ammo].id == bait_id
    else
        message(3, 'wardrobe slot: %d, id: %d':format(items.equipment.ammo, items.wardrobe[items.equipment.ammo].id))
        return items.wardrobe[items.equipment.ammo].id == bait_id
    end
end

function equip_bait()
    for slot,item in pairs(windower.ffxi.get_items().inventory) do
        if item.id == bait_id and item.status == 0 then
            message(1, 'equipping bait')
            message(3, 'inventory slot: %d, id: %d, status: %d':format(slot, item.id, item.status))
            windower.ffxi.set_equip(slot, 3, 0)
            return true
        end
    end
    for slot,item in pairs(windower.ffxi.get_items().wardrobe) do
        if item.id == bait_id and item.status == 0 then
            message(1, 'equipping bait')
            message(3, 'wardrobe slot: %d, id: %d, status: %d':format(slot, item.id, item.status))
            windower.ffxi.set_equip(slot, 3, 8)
            return true
        end
    end
    return false
end

-- inventory helper functions

function check_inventory()
    local items = windower.ffxi.get_items()
    message(2, 'checking inventory space')
    message(3, 'inventory count: %d, max: %d':format(items.count_inventory, items.max_inventory))
    return (items.max_inventory - items.count_inventory) > 1
end

function move_fish()
    local items = windower.ffxi.get_items()
    message(2, 'checking bag space')
    local empty_satchel = items.max_satchel - items.count_satchel
    message(3, 'satchel count: %d, max: %d':format(items.count_satchel, items.max_satchel))
    local empty_sack = items.max_sack - items.count_sack
    message(3, 'sack count: %d, max: %d':format(items.count_sack, items.max_sack))
    local empty_case = items.max_case - items.count_case
    message(3, 'case count: %d, max: %d':format(items.count_case, items.max_case))
    if (empty_satchel + empty_sack + empty_case) == 0 then
        return false
    end
    message(1, 'moving fish')
    local moved = 0
    for slot,item in pairs(items.inventory) do
        if item.id == fish_item_id and item.status == 0 then
            if empty_satchel > 0 then
                windower.ffxi.put_item(5, slot, item.count)
                empty_satchel = empty_satchel - 1
                moved = moved + 1
            elseif empty_sack > 0 then
                windower.ffxi.put_item(6, slot, item.count)
                empty_sack = empty_sack - 1
                moved = moved + 1
            elseif empty_case > 0 then
                windower.ffxi.put_item(7, slot, item.count)
                empty_sack = empty_sack - 1
                moved = moved + 1
            end
        end
    end
    message(3, 'fish moved: %d':format(moved))
    return moved > 0
end

function move_bait()
    local items = windower.ffxi.get_items()
    message(2, 'checking inventory space')
    local empty = items.max_inventory - items.count_inventory
    message(3, 'inventory count: %d, max: %d':format(items.count_inventory, items.max_inventory))
    local count = 20
    if empty < 2 then
        return false
    elseif empty <= count then
        count = math.floor(empty / 2)
    end
    message(1, 'moving bait')
    local moved = 0
    for slot,item in pairs(items.satchel) do
        if item.id == bait_id and count > 0 then
            windower.ffxi.get_item(5, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    for slot,item in pairs(items.sack) do
        if item.id == bait_id and count > 0 then
            windower.ffxi.get_item(6, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    for slot,item in pairs(items.case) do
        if item.id == bait_id and count > 0 then
            windower.ffxi.get_item(7, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    message(3, 'bait moved: %d':format(moved))
    return moved > 0
end

-- fatigue helper functions

function check_fatigued()
    local today = os.date('!%Y-%m-%d', os.time() + 32400)
    message(2, 'checking fatigue')
    if settings.fatigue.date ~= today then
        message(2, 'resetting fatigue')
        settings.fatigue.date = today
        settings.fatigue.remaining = 200
        settings:save()
    end
    message(3, 'catches until fatigued: %d':format(settings.fatigue.remaining))
    return settings.fatigue.remaining == 0
end

function update_fatigue(count)
    message(2, 'updating fatigue')
    settings.fatigue.remaining = settings.fatigue.remaining - count
    message(3, 'catches until fatigued: %d':format(settings.fatigue.remaining))
    settings:save()
end

-- fish id helper functions

function get_bite_id()
    for bite_id,item_id in pairs(settings.fish) do
        if item_id == fish_item_id then
            message(3, 'found fish bite id: %d, item id: %d':format(bite_id, fish_item_id))
            return tonumber(bite_id)
        end
    end
    message(1, 'bite id unknown')
    return nil
end

function update_fish()
    if last_item_id == fish_item_id then
        fish_bite_id = last_bite_id
    elseif fish_bite_id == last_bite_id then
        fish_bite_id = nil
    end
    settings.fish[tostring(last_bite_id)] = last_item_id
    message(3, 'updated fish bite id: %d, item id: %d':format(last_bite_id, last_item_id))
    last_item_id = nil
end

-- action functions

function catch()
    if running and not manual then
        local player = windower.ffxi.get_player()
        message(2, 'catching fish')
        windower.packets.inject_outgoing(0x110, 'IIIHH':pack(0xB10, player.id, 0, player.index, 3) .. catch_key)
    end
    manual = false
end

function release()
    if running and not manual then
        local player = windower.ffxi.get_player()
        message(2, 'releasing fish')
        windower.packets.inject_outgoing(0x110, 'IIIHHI':pack(0xB10, player.id, 200, player.index, 3, 0))
    end
    manual = false
end

function cast()
    if running then
        if check_fatigued() then
            message(0, 'fatigued')
            fisher_command('stop')
        elseif check_inventory() then
            if check_bait() then
                message(2, 'casting')
                cast_count = cast_count + 1
                windower.send_command('input /fish')
            elseif settings.equip and equip_bait() then
                message(2, 'casting in %d seconds':format(settings.delay.equip))
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.equip))
            elseif settings.move and move_bait() then
                message(2, 'casting in %d seconds':format(settings.delay.move))
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.move))
            else
                message(0, 'out of bait')
                fisher_command('stop')
            end
        elseif settings.move and move_fish() then
            message(2, 'casting in %d seconds':format(settings.delay.move))
            windower.send_command('wait %d; lua i fisher cast':format(settings.delay.move))
        else
            message(0, 'inventory full')
            fisher_command('stop')
        end
    end
end

-- event callback functions

function check_action(action)
    if running then
        local player_id = windower.ffxi.get_player().id
        for _,target in pairs(action.targets) do
            if target.id == player_id then
                message(0, 'action on player')
                message(3, 'action category: %d, actor: %d':format(action.category, action.actor_id))
                fisher_command('stop')
                return
            end
        end
    end
end

function check_status_change(new_status_id, old_status_id)
    if running and new_status_id ~= 0 and new_status_id ~= 50 then
        message(0, 'status changed')
        message(3, 'status new: %d, old: %d':format(new_status_id, old_status_id))
        fisher_command('stop')
    end
end

function check_chat_message(message, sender, mode, gm)
    if running and gm then
        message(0, 'incoming gm chat')
        message(3, 'chat from: %s, mode: %d':format(sender, mode))
        fisher_command('stop')
    end
end

function check_incoming_text(original, modified, original_mode, modified_mode, blocked)
    if running and original:find('You cannot fish here.') ~= nil then
        if error_retry then
            error_retry = false
            message(1, 'retrying cast')
            message(2, 'casting in %d seconds':format(settings.delay.cast))
            windower.send_command('wait %d; lua i fisher cast':format(settings.delay.cast))
        else
            message(0, 'cannot fish')
            fisher_command('stop')
        end
    end
end

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x115 then
            message(3, 'incoming fish info: ' .. original:hex())
            last_bite_id = original:unpack('I', 11)
            if last_item_id ~= nil then
                update_fish()
            end
            if fish_bite_id == last_bite_id or (fish_bite_id == nil and settings.fish[tostring(last_bite_id)] == nil) then
                bite_count = bite_count + 1
                catch_key = original:sub(21)
                local delay = fish_bite_id and catch_delay or settings.delay.unknown
                message(2, 'catching fish in %d seconds':format(delay))
                windower.send_command('wait %d; lua i fisher catch':format(delay))
            else
                message(2, 'releasing fish in %d seconds':format(settings.delay.release))
                windower.send_command('wait %d; lua i fisher release':format(settings.delay.release))
            end
        elseif id == 0x2A and windower.ffxi.get_player().id == original:unpack('I', 5) then
            message(3, 'incoming fish intuition: ' .. original:hex())
            last_item_id = original:unpack('I', 9)
        elseif id == 0x27 and windower.ffxi.get_player().id == original:unpack('I', 5) then
            message(3, 'incoming fish caught: ' .. original:hex())
            catch_count = catch_count + 1
            last_item_id = original:unpack('I', 17)
            update_fish()
            windower.send_command('lua i fisher update_fatigue 1')
        end
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x110 then
            message(3, 'outgoing fishing action: ' .. original:hex())
            if original:byte(15) == 4 then
                message(2, 'casting in %d seconds':format(settings.delay.cast))
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.cast))
            elseif original:byte(15) == 3 and original:unpack('H', 3) ~= 0 then
                message(2, 'manual catch or release')
                manual = true
            end
        elseif id == 0x1A then
            if original:unpack('H', 11) == 14 then
                message(3, 'outgoing fish command: ' .. original:hex())
                error_retry = true
                last_item_id = nil
            else
                message(0, 'outgoing command')
                fisher_command('stop')
            end
        end
    end
end

function fisher_command(...)
    if #arg == 4 and arg[1]:lower() == 'start' then
        if running then
            windower.add_to_chat(167, 'already fishing')
            return
        end
        bait_id = tonumber(arg[2])
        if bait_id == nil then
            _,bait_id = res.items:with('name', arg[2])
            if bait_id == nil then
                windower.add_to_chat(167, 'invalid bait name')
                return
            end
        end
        fish_item_id = tonumber(arg[3])
        if fish_item_id == nil then
            _,fish_item_id = res.items:with('name', arg[3])
            if fish_item_id == nil then
                windower.add_to_chat(167, 'invalid fish name')
                return
            end
        end
        catch_delay = tonumber(arg[4])
        if catch_delay == nil then
            windower.add_to_chat(167, 'invalid catch delay')
            return
        end
        cast_count = 0
        bite_count = 0
        catch_count = 0
        running = true
        message(1, 'started fishing')
        message(2, 'bait id: %s, fish id: %s, catch delay: %s':format(bait_id, fish_item_id, catch_delay))
        fish_bite_id = get_bite_id()
        error_retry = true
        cast()
    elseif #arg == 1 and arg[1]:lower() == 'restart' then
        if running then
            windower.add_to_chat(167, 'already fishing')
            return
        end
        if bait_id == nil or fish_item_id == nil or catch_delay == nil then
            windower.add_to_chat(167, 'invalid bait, fish or catch delay')
            return
        end
        running = true
        message(1, 'started fishing')
        fish_bite_id = get_bite_id()
        error_retry = true
        cast()
    elseif #arg == 1 and arg[1]:lower() == 'stop' then
        if not running then
            windower.add_to_chat(167, 'not fishing')
            return
        end
        running = false
        manual = false
        message(1, 'stopped fishing')
        if log_file ~= nil then
            log_file:close()
            log_file = nil
        end
    elseif #arg == 2 and arg[1]:lower() == 'chat' then
        settings.chat = tonumber(arg[2]) or 1
        windower.add_to_chat(200, 'chat message level: %s':format(settings.chat >= 0 and settings.chat or 'off'))
        settings:save()
    elseif #arg == 2 and arg[1]:lower() == 'log' then
        settings.log = tonumber(arg[2]) or -1
        windower.add_to_chat(200, 'log message level: %s':format(settings.log >= 0 and settings.log or 'off'))
        settings:save()
        if settings.log < 0 and log_file ~= nil then
            log_file:close()
            log_file = nil
        end
    elseif #arg == 2 and arg[1]:lower() == 'equip' then
        settings.equip = (arg[2]:lower() == 'on')
        windower.add_to_chat(200, 'equip bait: %s':format(settings.equip and 'on' or 'off'))
        settings:save()
    elseif #arg == 2 and arg[1]:lower() == 'move' then
        settings.move = (arg[2]:lower() == 'on')
        windower.add_to_chat(200, 'move bait and fish: %s':format(settings.move and 'on' or 'off'))
        settings:save()
    elseif #arg == 1 and arg[1]:lower() == 'reset' then
        windower.add_to_chat(200, 'resetting fish database')
        settings.fish = {}
        settings:save()
        fish_bite_id = nil
    elseif #arg == 1 and arg[1]:lower() == 'stats' then
        local break_count = bite_count - catch_count
        local bite_rate = 0
        local break_rate = 0
        local catch_rate = 0
        if cast_count ~= 0 then
            bite_rate = (bite_count / cast_count) * 100
            break_rate = (break_count / cast_count) * 100
            catch_rate = (catch_count / cast_count) * 100
        end
        local break_bite_rate = 0
        local catch_bite_rate = 0
        if bite_count ~= 0 then
            break_bite_rate = (break_count / bite_count) * 100
            catch_bite_rate = (catch_count / bite_count) * 100
        end
        if running == false then
            check_fatigued()
        end
        windower.add_to_chat(200, 'casts: %d, remaining fatigue: %d':format(cast_count, settings.fatigue.remaining))
        windower.add_to_chat(200, 'bites: %d, bite rate: %d%%':format(bite_count, bite_rate))
        windower.add_to_chat(200, 'catches: %d, catch rate: %d%%, catch/bite rate: %d%%':format(catch_count, catch_rate, catch_bite_rate))
        windower.add_to_chat(200, 'breaks: %d, break rate: %d%%, break/bite rate: %d%%':format(break_count, break_rate, break_bite_rate))
    elseif #arg == 2 and arg[1]:lower() == 'fatigue' then
        local count = tonumber(arg[2])
        if count == nil then
            windower.add_to_chat(167, 'invalid count')
        elseif count < 0 then
            if running == false then
                check_fatigued()
            end
            settings.fatigue.remaining = settings.fatigue.remaining + count
            windower.add_to_chat(200, 'remaining fatigue: %d':format(settings.fatigue.remaining))
            settings:save()
        else
            settings.fatigue.remaining = count
            windower.add_to_chat(200, 'remaining fatigue: %d':format(settings.fatigue.remaining))
            settings:save()
        end
    else
        windower.add_to_chat(167, 'usage: fisher start <bait> <fish> <catch delay>')
        windower.add_to_chat(167, '        fisher restart')
        windower.add_to_chat(167, '        fisher stop')
        windower.add_to_chat(167, '        fisher chat <level>')
        windower.add_to_chat(167, '        fisher log <level>')
        windower.add_to_chat(167, '        fisher equip <on/off>')
        windower.add_to_chat(167, '        fisher move <on/off>')
        windower.add_to_chat(167, '        fisher reset')
        windower.add_to_chat(167, '        fisher stats')
        windower.add_to_chat(167, '        fisher fatigue <count>')
    end
end

-- register event callbacks

windower.register_event('action', check_action)
windower.register_event('status change', check_status_change)
windower.register_event('chat message', check_chat_message)
windower.register_event('incoming text', check_incoming_text)
windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
windower.register_event('addon command', fisher_command)
