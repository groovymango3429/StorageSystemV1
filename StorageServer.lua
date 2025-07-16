-- Place in ServerScriptService

--[[
  StorageServer.lua
  Handles:
    - Storage bin data for each shelf
    - Communication with clients for opening, updating, depositing, withdrawing storage
    - Ensures stackData sent to client includes .Image (TextureId) from ServerStorage.Tools
    - Inventory/Storage stack mutation (add/remove)
    - Uses StackImageUtil module for attaching .Image
    - Example logic, adjust for your game as needed
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Signal = require(ReplicatedStorage.Modules.Signal) -- Your remote event wrapper
local StackImageUtil = require(script.Parent.StackImageUtil) -- Adjust path as needed

-- Storage data in-memory (you may want to persist this)
local ShelfData = {} -- [storageId] = { Items = {stack, ...}, MaxStacks = number, Owner = player }

-- UTILITIES

local function getPlayerInventory(player)
    -- Replace with your actual inventory management
    player.Inventory = player.Inventory or { Inventory = {} }
    return player.Inventory
end

local function findStackById(stacks, stackId)
    for idx, stack in ipairs(stacks) do
        if stack.StackId == stackId then
            return idx, stack
        end
    end
    return nil
end

-- STORAGE OPEN
Signal.Listen("Storage:Open", function(player, storageId)
    local shelf = ShelfData[storageId]
    if not shelf or shelf.Owner ~= player then
        Signal.FireClient(player, "Storage:Error", "Storage not found or not owned by you")
        return
    end
    local stacksToSend = StackImageUtil.AttachImagesToStacks(shelf.Items)
    Signal.FireClient(player, "Storage:Open", storageId, stacksToSend, shelf.MaxStacks)
end)

-- STORAGE DEPOSIT
Signal.Listen("Storage:Deposit", function(player, storageId, stackId)
    local shelf = ShelfData[storageId]
    if not shelf or shelf.Owner ~= player then
        Signal.FireClient(player, "Storage:Error", "Storage not found or not owned by you")
        return
    end

    local inv = getPlayerInventory(player)
    local invIdx, invStack = findStackById(inv.Inventory, stackId)
    if not invIdx or not invStack then
        Signal.FireClient(player, "Storage:Error", "Item not found in inventory")
        return
    end

    -- Add to shelf if not full
    if #shelf.Items >= shelf.MaxStacks then
        Signal.FireClient(player, "Storage:Error", "Storage is full")
        return
    end

    table.insert(shelf.Items, invStack)
    table.remove(inv.Inventory, invIdx)

    -- Update both GUIs
    Signal.FireClient(player, "Storage:Update", storageId, StackImageUtil.AttachImagesToStacks(shelf.Items), shelf.MaxStacks)
    Signal.FireClient(player, "InventoryClient:Update", inv)
end)

-- STORAGE WITHDRAW
Signal.Listen("Storage:Withdraw", function(player, storageId, stackId)
    local shelf = ShelfData[storageId]
    if not shelf or shelf.Owner ~= player then
        Signal.FireClient(player, "Storage:Error", "Storage not found or not owned by you")
        return
    end

    local idx, shelfStack = findStackById(shelf.Items, stackId)
    if not idx or not shelfStack then
        Signal.FireClient(player, "Storage:Error", "Item not found in storage")
        return
    end

    -- Add to player inventory
    local inv = getPlayerInventory(player)
    table.insert(inv.Inventory, shelfStack)
    table.remove(shelf.Items, idx)

    -- Update both GUIs
    Signal.FireClient(player, "Storage:Update", storageId, StackImageUtil.AttachImagesToStacks(shelf.Items), shelf.MaxStacks)
    Signal.FireClient(player, "InventoryClient:Update", inv)
end)

-- Example function for initializing a storage shelf for a player (call when plot/plot object is created)
function SetupShelfForPlayer(player, storageId, maxStacks)
    ShelfData[storageId] = {
        Items = {}, -- start empty or load from datastore
        MaxStacks = maxStacks or 8,
        Owner = player
    }
end

-- Example for cleaning up shelf data (call on plot removal/player leave)
function CleanupShelf(storageId)
    ShelfData[storageId] = nil
end

-- Optional: player removal cleanup
Players.PlayerRemoving:Connect(function(player)
    for id, shelf in pairs(ShelfData) do
        if shelf.Owner == player then
            ShelfData[id] = nil
        end
    end
end)

return {
    ShelfData = ShelfData,
    SetupShelfForPlayer = SetupShelfForPlayer,
    CleanupShelf = CleanupShelf
}