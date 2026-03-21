--[[
    Opium Security - Entité Moniteur de Sécurité (Shared)
    Permet de visualiser les caméras d'un groupe depuis un écran.
]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.PrintName    = "Moniteur de Sécurité"
ENT.Author       = "Opium Security"
ENT.Category     = "Opium Security"
ENT.Spawnable    = true
ENT.AdminOnly    = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "MonitorGroup") -- Groupe de caméras liées
    self:NetworkVar("Entity", 0, "MonitorUser")   -- Joueur qui regarde actuellement
end
