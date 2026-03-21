--[[
    Opium Security - Entité Moniteur de Sécurité (Server)
    Le moniteur doit être dans un groupe pour fonctionner.
    Quand un joueur appuie sur E, il ouvre la vue de la première caméra active du groupe.
]]

AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

OpiumSecurity = OpiumSecurity or {}
OpiumSecurity.Monitors = OpiumSecurity.Monitors or {}

-- Network string pour le moniteur (message quand pas de groupe)
util.AddNetworkString("opium_monitor_nogroup")

function ENT:Initialize()
    self:SetModel("models/props_lab/monitor01b.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetMonitorGroup("")

    table.insert(OpiumSecurity.Monitors, self)
end

function ENT:OnRemove()
    if OpiumSecurity.Monitors then
        table.RemoveByValue(OpiumSecurity.Monitors, self)
    end

    -- Si un joueur regardait via ce moniteur, le libérer
    local user = self:GetMonitorUser()
    if IsValid(user) then
        net.Start("opium_camera_exit")
        net.Send(user)
    end
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local group = self:GetMonitorGroup()

    -- Vérifier que le moniteur est dans un groupe
    if not group or group == "" then
        activator:ChatPrint("[Opium Security] Ce moniteur n'est associé à aucun groupe. Utilisez l'outil de liaison pour l'ajouter à un groupe.")
        return
    end

    -- Trouver la première caméra active du groupe
    local firstCam = nil
    for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
        if IsValid(cam) and cam:GetCamActive() and cam:GetCamGroup() == group then
            firstCam = cam
            break
        end
    end

    if not IsValid(firstCam) then
        local displayName = OpiumSecurity.GetGroupName(group)
        activator:ChatPrint("[Opium Security] Aucune caméra active dans le groupe \"" .. displayName .. "\".")
        return
    end

    -- Ouvrir la vue caméra pour le joueur
    firstCam:SetCamUser(activator)
    self:SetMonitorUser(activator)

    net.Start("opium_camera_open")
        net.WriteEntity(firstCam)
    net.Send(activator)
end

-- Nettoyer quand un joueur se déconnecte
hook.Add("PlayerDisconnected", "OpiumSecurity_MonitorCleanup", function(ply)
    for _, monitor in ipairs(ents.FindByClass("ent_security_monitor")) do
        if IsValid(monitor) and monitor:GetMonitorUser() == ply then
            monitor:SetMonitorUser(NULL)
        end
    end
end)

-- Nettoyer le moniteur quand le joueur quitte la vue caméra
timer.Create("OpiumSecurity_MonitorExitCleanup", 1, 0, function()
    for _, monitor in ipairs(ents.FindByClass("ent_security_monitor")) do
        if not IsValid(monitor) then continue end
        local user = monitor:GetMonitorUser()
        if not IsValid(user) then continue end

        -- Vérifier si le joueur est encore en train de regarder une caméra du groupe
        local group = monitor:GetMonitorGroup()
        local stillViewing = false

        for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
            if IsValid(cam) and cam:GetCamGroup() == group and cam:GetCamUser() == user then
                stillViewing = true
                break
            end
        end

        if not stillViewing then
            monitor:SetMonitorUser(NULL)
        end
    end
end)
