--[[
    Opium Security - Entité Caméra de Sécurité (Server)
]]

AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

OpiumSecurity = OpiumSecurity or {}
OpiumSecurity.Config = OpiumSecurity.Config or {}

-- Enregistrer les network strings ici car l'entité peut se charger avant autorun/server
util.AddNetworkString("opium_camera_open")
util.AddNetworkString("opium_camera_exit")
util.AddNetworkString("opium_camera_switch")
util.AddNetworkString("opium_camera_notify")
util.AddNetworkString("opium_camera_wanted")
util.AddNetworkString("opium_camera_viewdata")

function ENT:Initialize()
    self:SetModel("models/maxofs2d/camera.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetCamActive(true)
    self:SetCamName("CAM-" .. math.random(1000, 9999))
    self:SetCamGroup("")

    -- Enregistrer la caméra dans le système global
    OpiumSecurity.Cameras = OpiumSecurity.Cameras or {}
    table.insert(OpiumSecurity.Cameras, self)
end

function ENT:OnRemove()
    -- Retirer la caméra du système global
    if OpiumSecurity.Cameras then
        table.RemoveByValue(OpiumSecurity.Cameras, self)
    end

    -- Si un joueur regardait cette caméra, le libérer
    local user = self:GetCamUser()
    if IsValid(user) then
        net.Start("opium_camera_exit")
        net.Send(user)
    end
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if not self:GetCamActive() then
        activator:ChatPrint("[Opium Security] Cette caméra est désactivée.")
        return
    end

    -- Vérifier si le joueur est autorisé (police ou propriétaire)
    -- Pour l'instant, tout le monde peut utiliser les caméras
    -- Décommente la ligne ci-dessous pour restreindre à la police :
    -- if not OpiumSecurity.IsPolice(activator) then
    --     activator:ChatPrint("[Opium Security] Accès refusé.")
    --     return
    -- end

    -- Ouvrir l'interface de la caméra pour le joueur
    net.Start("opium_camera_open")
        net.WriteEntity(self)
    net.Send(activator)

    self:SetCamUser(activator)
end

--- Retourne la position de vue de la caméra (légèrement devant le modèle)
function ENT:GetViewPos()
    return self:GetPos() + self:GetForward() * 5 + self:GetUp() * 5
end

--- Retourne l'angle de vue de la caméra
function ENT:GetViewAngle()
    return self:GetAngles()
end

-- ============================================================================
-- RÉCEPTION RÉSEAU (placé ici car ce fichier est garanti de se charger)
-- ============================================================================

-- Le joueur quitte la vue caméra
net.Receive("opium_camera_exit", function(len, ply)
    for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
        if IsValid(cam) and cam:GetCamUser() == ply then
            cam:SetCamUser(NULL)
        end
    end
end)

-- Le joueur change de caméra (next/previous)
net.Receive("opium_camera_switch", function(len, ply)
    local direction = net.ReadInt(8)
    local clientCam = net.ReadEntity()

    -- Trouver la caméra actuelle via CamUser (serveur-autoritaire)
    local currentCam = nil
    local allCameras = ents.FindByClass("ent_security_cam")

    for _, cam in ipairs(allCameras) do
        if IsValid(cam) and cam:GetCamUser() == ply then
            currentCam = cam
            break
        end
    end

    -- Fallback : entité envoyée par le client
    if not IsValid(currentCam) and IsValid(clientCam) and clientCam:GetClass() == "ent_security_cam" then
        currentCam = clientCam
    end

    if not IsValid(currentCam) then return end

    local currentGroup = currentCam:GetCamGroup()

    -- Libérer la caméra actuelle
    currentCam:SetCamUser(NULL)

    -- Trouver les caméras du même groupe
    local cameras = {}
    for _, cam in ipairs(allCameras) do
        if IsValid(cam) and cam:GetCamActive() and cam:GetCamGroup() == currentGroup then
            table.insert(cameras, cam)
        end
    end

    if #cameras == 0 then
        net.Start("opium_camera_exit")
        net.Send(ply)
        return
    end

    if #cameras == 1 then
        ply:ChatPrint("[Opium Security] Aucune autre caméra dans ce groupe.")
        currentCam:SetCamUser(ply)
        return
    end

    -- Trouver l'index actuel
    local currentIndex = 1
    for i, cam in ipairs(cameras) do
        if cam == currentCam then
            currentIndex = i
            break
        end
    end

    -- Calculer le nouvel index
    local newIndex = currentIndex + direction
    if newIndex > #cameras then newIndex = 1 end
    if newIndex < 1 then newIndex = #cameras end

    local newCam = cameras[newIndex]
    newCam:SetCamUser(ply)

    -- Envoyer la nouvelle caméra au client
    net.Start("opium_camera_open")
        net.WriteEntity(newCam)
    net.Send(ply)
end)

-- Le joueur déclare manuellement un joueur recherché
net.Receive("opium_camera_wanted", function(len, ply)
    if not OpiumSecurity.IsPolice(ply) then
        ply:ChatPrint("[Opium Security] Vous n'avez pas l'autorité pour déclarer quelqu'un recherché.")
        return
    end

    local target = net.ReadEntity()
    if not IsValid(target) or not target:IsPlayer() then return end

    local reason = net.ReadString()
    if reason == "" then reason = "Déclaré recherché par la police" end

    -- Marquer comme recherché (fallback simple)
    target:SetNWBool("opium_wanted", true)
    target:SetNWString("opium_wanted_reason", reason)

    timer.Create("opium_unwanted_" .. target:SteamID(), 300, 1, function()
        if IsValid(target) then
            target:SetNWBool("opium_wanted", false)
            target:SetNWString("opium_wanted_reason", "")
        end
    end)

    ply:ChatPrint("[Opium Security] " .. target:Nick() .. " a été déclaré recherché.")
    target:ChatPrint("[Opium Security] Vous avez été déclaré recherché : " .. reason)
end)

-- Nettoyer quand un joueur se déconnecte
hook.Add("PlayerDisconnected", "OpiumSecurity_Cleanup", function(ply)
    for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
        if IsValid(cam) and cam:GetCamUser() == ply then
            cam:SetCamUser(NULL)
        end
    end
end)
