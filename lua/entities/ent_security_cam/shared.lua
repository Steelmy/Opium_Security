--[[
    Opium Security - Entité Caméra de Sécurité (Shared)
]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.PrintName    = "Caméra de Sécurité"
ENT.Author       = "Opium Security"
ENT.Category     = "Opium Security"
ENT.Spawnable    = true
ENT.AdminOnly    = false

-- Networked variable : ID unique de la caméra pour le système
function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "CamName")
    self:NetworkVar("String", 1, "CamGroup") -- Groupe de caméras liées
    self:NetworkVar("Bool", 0, "CamActive")
    self:NetworkVar("Entity", 0, "CamUser") -- Joueur qui regarde actuellement
end
