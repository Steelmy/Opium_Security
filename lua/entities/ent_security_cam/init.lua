--[[
    Opium Security - Entité Caméra de Sécurité (Server)
]]

AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

OpiumSecurity = OpiumSecurity or {}
OpiumSecurity.Config = OpiumSecurity.Config or {}

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
