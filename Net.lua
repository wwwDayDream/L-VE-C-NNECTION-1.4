--[[ LICENSE
Copyright (c) 2015-2018 Nicholas Scott
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
Except as contained in this notice, the name(s) of the above copyright holders
shall not be used in advertising or otherwise to promote the sale, use or
other dealings in this Software without prior written authorization.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
]]--
 
local Socket = require( "socket" )
local net = {}
 
net.event = {}
net.event.client = {}
net.event.server = {}
net.event.client.connect = function( ip, port ) end
net.event.client.receive = function( data, dt, cmd, param ) end
net.event.client.disconnect = function() end
net.event.client.cmdRegistered = function( cmd, functionS ) end
net.event.client.send = function( table, cmd, param  ) end
net.event.client.kickedFromServer = function( reason ) end
 
net.event.server.userConnected = function( id ) end
net.event.server.userDisconnected = function( id ) end
net.event.server.userTimedOut = function( id ) end
net.event.server.userKicked = function( id, reason ) end
net.event.server.receive = function( data, dt, id, cmd, param ) end
net.event.server.connect = function( port ) end
net.event.server.disconnect = function() end
net.event.server.cmdRegistered = function( cmd, functionS ) end
net.event.server.send = function( table, cmd, param, id ) end
 
net.client = {}
net.client.ip = nil
net.client.port = nil
 
net.server = {}
net.server.port = nil
 
net.commands = {}
net.SERVER = false
net.CLIENT = false
net.users = {}
net.maxPing = 0
net.currentPing = 0
net.connected = false
 
net.null = string.char(30)
net.one = string.char(31)
net.defnull = net.null
net.defone = net.one
 
local function registerAllCMDS()
        if net.CLIENT then
 
        net:registerCMD( "print", function( table, param )
                print( "Server Message: "..param)
        end )
 
        net:registerCMD( "kick", function( table, param, t )
                net.event.client.kickedFromServer( param )
                print( "Kicked from server for reason: "..param )
                net:disconnect()
        end )
 
        end
        if net.SERVER then
 
        net:registerCMD( "disconnect", function( table, param, id )
                net.event.server.userDisconnected( id )
                print( "User ["..id.."] disconnected" )
                net.users[id] = nil
        end )
 
        net:registerCMD( "print", function( table, param, id )
                print( "User ["..id.."] "..param)
        end )
 
        net:registerCMD( "ping", function( table, param, id, t )
                if not net.users[id] then
                        net.event.server.userConnected( id )
                        net.users[id] = {ping = t*1000}
                        print( "User ["..id.."] connected" )
                end
                if net.users[id] then
                        net.users[id].ping = 0
                end
        end )
 
        end
end
 
function net:commandsRegistered()
        return net.commands
end
 
function net:connectedUsers()
        if net.CLIENT then return end
        return net.users
end
 
function net:kickUser( id, reason )
        if net.CLIENT then return end
        if not net.users[id] then return end
        local reason2 = reason or "Kicked by administrator"
        net.event.server.userKicked( id, reason2 )
        net:send( {}, "kick", reason2, id)
        print( "User ["..id.."] was kicked for reason: "..reason2 )
        net.users[id] = nil
end
 
function net:isServer()
        return net.SERVER
end
 
function net:setMaxPing( ping )
        net.maxPing = ping
end
 
function net:isClient()
        return net.CLIENT
end
 
function net:init( what )
 
        local whatlower = string.lower( what )
        if whatlower == "client" then
                print( "Created UDP Client!" )
                net.CLIENT = true
                net:setMaxPing( 100 )
                registerAllCMDS()
        elseif whatlower == "server" then
                print( "Created UDP Server!" )
                net.SERVER = true
                net:setMaxPing( 300 )
                registerAllCMDS()
        end
 
end
 
function net:update(dt)
        if net.CLIENT then
 
                if net.connected then
                        net.currentPing = net.currentPing + dt*1000
                        if net.currentPing > net.maxPing then
                                net:send( {}, "ping", "" )
                                net.currentPing = 0
                        end
                end
 
                local data1, ip, port = socket:receivefrom()
 
                if ip ~= net.client.ip then return end
                if port ~= net.client.port then return end
 
 
                if net.connected then
                        local data = data1
 
                        if data then
                                received_table = net:decode(data)
                       
                                net.event.client.receive( received_table, dt, received_table.Commmand, received_table.Param )
 
                                if net.commands[received_table.Command] then
                                        local tempFunction = net.commands[received_table.Command]
                                        local tempParam = received_table.Param
                                        if tempFunction then
                                                tempFunction( received_table, tempParam, dt )
                                        end
                                else
                                        print( "Error: Network command "..received_table.Command.." is not supported!" )
                                end
                        end
                end
 
        end
 
        if net.SERVER then
 
                for i,v in pairs( net.users ) do
                        v.ping = v.ping + dt*1000
                        if v.ping >= net.maxPing then
                                net.event.server.userTimedOut( i )
                                print( "User ["..i.."] timed out")
                                net.users[i] = nil
                        end
                end
 
                local data, ip, port = socket:receivefrom()
 
                if data then
 
                        local id = ip..":"..port
 
                        received_table = net:decode(data)
 
                        net.event.server.receive( received_table, dt, id, received_table.Command, received_table.Param )
 
                        if net.commands[received_table.Command] then
                                local tempFunction = net.commands[received_table.Command]
                                local tempParam = received_table.Param
                                if tempFunction then
                                        tempFunction( received_table, tempParam, id, dt )
                                end
                        else
                                print( "Error: Network command "..received_table.Command.." is not supported!" )
                        end
                end
        end
 
end
 
function net:connect( ip, port )
 
        if net.CLIENT then
                if not ip then return end
                if not port then port = 20024 end
 
                socket = Socket.udp()
                socket:settimeout( 0 )
 
                net.client.ip = ip
                net.client.port = port
 
                net.connected = true
 
                net.event.client.connect( ip, port )
 
                net:send( {}, "ping", "" )
 
                print( "Sending to server: '"..ip..":"..port.."'")
        end
 
        if net.SERVER then
                if not port then port = 20024 end
                net.server.port = port
 
                socket = Socket.udp()
                socket:settimeout( 0 )
                socket:setsockname( "*", port )
 
                net.connected = true
                net.event.server.connect( port )
                print( "Listening on port: '"..port.."'")
        end
 
end
 
function net:disconnect()
 
        if net.CLIENT then
                net.event.client.disconnect()
                net:send( {}, "disconnect" )
 
                net.client.ip = nil
                net.client.port = nil
                net.connected = false
 
                socket:close()
 
                print( "Disconnnected from server connection" )
        end
 
        if net.SERVER then
                net.event.server.disconnect()
 
                net.server.port = nil
                net.connected = false
 
                socket:close()
 
                print( "No longer listening to any ports" )
        end
 
end
 
function net:registerCMD( cmd, functionS )
        if net.CLIENT then net.event.client.cmdRegistered( cmd, functionS ) end
        if net.SERVER then net.event.server.cmdRegistered( cmd, functionS ) end
        if not cmd then return end
        if not functionS then return end
        if net.commands[cmd] then return end
 
        net.commands[cmd] = functionS
        print( "Successfully Created Command: '"..cmd.."'" )
end
 
function net:send( table, cmd, param, id )
 
        if net.CLIENT then
                if not net.connected then return end
                if type(table) == "table" then
                        net.event.client.send( table, cmd, param )
                        table.Command = cmd or ""
                        table.Param = param or ""
                        socket:sendto( net:encode( table ), net.client.ip, net.client.port )
                else
                        print( type(table).." is not supported by 'net:send'. Please send only tables!" )
                end
        end
 
        if net.SERVER then
                if not net.connected then return end
                if not id then error( "No ID Supplied In net_send!" ) end
                if type(table) == "table" then
                        net.event.server.send( table, cmd, param, id )
                        table.Command = cmd or ""
                        table.Param = param or ""
                        local ip, port = id:match( "^(.-):(%d+)$" )
                        socket:sendto( net:encode( table ), ip, tonumber( port ) )
                else
                        print( type(table).." is not supported by 'net:send'. Please send only tables!" )
                end
        end
end
 
function net:seps(null, one)
        null = null or net.defnull
        one = one or net.defone
        net.null = null
        net.one = one
end
 
function net:encode(t)
        local result = ""
        for i, v in pairs(t) do
                result = result .. net:encodevalue(i, v)
        end
        return result
end
 
function net:encodevalue(i, v)
        local id = ""
        local typev = type(v)
        if typev == "string" then id = "S"
        elseif typev == "number" then id = "N"
        elseif typev == "boolean" then id = "B"
        elseif typev == "userdata"  then id = "U"
        elseif typev == "nil" then id = "0"
        else error("Type " .. typev .. " is not supported by Binary.lua") return
        end
        return tostring(id .. net.one .. i .. net.one .. tostring(v) .. net.null)
end
 
function net:decode(s)
        -- if type(s) ~= "string" then
        --      print("You can only decode strings. If you think you're still passing a string into this function you may have forgotten to use a : instead of a . ")
        -- end
        local t = {}
        local i, v
        for s2 in string.gmatch(s, "[^" .. net.null .. "]+") do
                i, v = net:decodevalue(s2)
                t[i] = v
        end
        return t
end
 
function net:decodevalue(s)
        local id = s:sub(1, 1)
        s = s:sub(3)
        local len = s:find(net.one)
        local i = s:sub(1, len-1)
        local v = s:sub(len+1)
        if id == "N" then v = tonumber(v)
        elseif id == "B" then v = (v == "true")
        elseif id == "0" then v = nil
	    end
        return i, v
end
 
 
return net
