--[[
    Opium Security - Tool Gun : Liaison de Caméras
    Permet de relier des caméras en groupes via le Tool Gun.
    - Clic gauche : ajouter une caméra au groupe en cours
    - Clic droit : retirer une caméra de son groupe
    - Rechargement : finaliser le groupe et en commencer un nouveau
]]

TOOL.Category    = "Opium Security"
TOOL.Name        = "#tool.opium_camera_link.name"
TOOL.Command     = nil
TOOL.ConfigName  = ""

TOOL.ClientConVar["group"] = ""

TOOL.Information = {
    { name = "left" },
    { name = "right" },
    { name = "reload" },
}

if CLIENT then
    language.Add("tool.opium_camera_link.name", "Liaison Caméras")
    language.Add("tool.opium_camera_link.desc", "Relie les caméras de sécurité en groupes de vidéosurveillance")
    language.Add("tool.opium_camera_link.left", "Ajouter la caméra au groupe actuel")
    language.Add("tool.opium_camera_link.right", "Retirer la caméra de son groupe")
    language.Add("tool.opium_camera_link.reload", "Finaliser et commencer un nouveau groupe")
    language.Add("tool.opium_camera_link.0", "Clic gauche sur une caméra pour commencer un groupe")
    language.Add("tool.opium_camera_link.1", "Clic gauche sur une autre caméra pour l'ajouter au groupe. Rechargez pour finaliser.")
end

-- État serveur : groupe actif par joueur
local ActiveGroups = {}
local groupCounter = 0

-- ============================================================================
-- FONCTIONS UTILITAIRES
-- ============================================================================

local function IsCamera(ent)
    return IsValid(ent) and ent:GetClass() == "ent_security_cam"
end

local function GetGroupCameraCount(groupName)
    if groupName == "" then return 0 end
    local count = 0
    for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
        if IsValid(cam) and cam:GetCamGroup() == groupName then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- TOOL ACTIONS
-- ============================================================================

function TOOL:LeftClick(trace)
    if not IsCamera(trace.Entity) then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    local cam = trace.Entity

    -- Si pas de groupe actif, en créer un
    if not ActiveGroups[ply] then
        local customName = self:GetClientInfo("group")
        customName = string.Trim(customName or "")

        local groupName
        if customName ~= "" then
            groupName = string.sub(customName, 1, 32)
        else
            groupCounter = groupCounter + 1
            groupName = "GRP-" .. groupCounter
        end

        ActiveGroups[ply] = { name = groupName, count = 0 }
        self:SetStage(1)
    end

    local group = ActiveGroups[ply]
    cam:SetCamGroup(group.name)
    group.count = group.count + 1

    ply:ChatPrint("[Opium Security] " .. cam:GetCamName() .. " ajoutée au groupe \"" .. group.name .. "\" (" .. group.count .. " caméras)")
    ply:EmitSound("buttons/button14.wav")

    return true
end

function TOOL:RightClick(trace)
    if not IsCamera(trace.Entity) then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    local cam = trace.Entity
    local oldGroup = cam:GetCamGroup()

    if oldGroup == "" then
        ply:ChatPrint("[Opium Security] " .. cam:GetCamName() .. " n'appartient à aucun groupe.")
        return true
    end

    cam:SetCamGroup("")

    -- Mettre à jour le compteur si c'est le groupe actif
    if ActiveGroups[ply] and ActiveGroups[ply].name == oldGroup then
        ActiveGroups[ply].count = math.max(0, ActiveGroups[ply].count - 1)
    end

    local remaining = GetGroupCameraCount(oldGroup)
    ply:ChatPrint("[Opium Security] " .. cam:GetCamName() .. " retirée du groupe \"" .. oldGroup .. "\" (" .. remaining .. " restantes)")
    ply:EmitSound("buttons/button15.wav")

    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()

    if ActiveGroups[ply] then
        local group = ActiveGroups[ply]
        ply:ChatPrint("[Opium Security] Groupe \"" .. group.name .. "\" finalisé avec " .. group.count .. " caméras.")
        ActiveGroups[ply] = nil
        self:SetStage(0)
    else
        ply:ChatPrint("[Opium Security] Aucun groupe en cours.")
    end

    return true
end

function TOOL:Holster()
    if SERVER and IsValid(self:GetOwner()) then
        ActiveGroups[self:GetOwner()] = nil
    end
end

function TOOL:Deploy()
    if SERVER then
        self:SetStage(ActiveGroups[self:GetOwner()] and 1 or 0)
    end
end

-- Nettoyage quand un joueur se déconnecte
hook.Add("PlayerDisconnected", "OpiumSecurity_ToolCleanup", function(ply)
    ActiveGroups[ply] = nil
end)

-- ============================================================================
-- HUD CLIENT
-- ============================================================================

if CLIENT then
    function TOOL:DrawHUD()
        local trace = LocalPlayer():GetEyeTrace()
        local colors = OpiumSecurity and OpiumSecurity.Config and OpiumSecurity.Config.Colors

        if not colors then return end

        local sw, sh = ScrW(), ScrH()
        local cx, cy = sw / 2, sh / 2

        -- Info sur la caméra visée
        if IsCamera(trace.Entity) then
            local cam = trace.Entity
            local group = cam:GetCamGroup()
            local name = cam:GetCamName()

            local panelW, panelH = 300, 70
            local px, py = cx - panelW / 2, cy + 40

            if group and group ~= "" then
                panelH = 90
            end

            draw.RoundedBox(6, px, py, panelW, panelH, ColorAlpha(colors.Background, 220))
            surface.SetDrawColor(ColorAlpha(colors.Border, 200))
            surface.DrawOutlinedRect(px, py, panelW, panelH, 1)

            -- Barre accent en haut
            surface.SetDrawColor(colors.Accent)
            surface.DrawRect(px, py, panelW, 3)

            draw.SimpleText(name, "OpiumSec_Subtitle", cx, py + 18, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            if group and group ~= "" then
                local count = GetGroupCameraCount(group)
                draw.SimpleText("Groupe : " .. group, "OpiumSec_Body", cx, py + 42, colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                draw.SimpleText(count .. " caméra(s) liée(s)", "OpiumSec_Small", cx, py + 62, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            else
                draw.SimpleText("Aucun groupe", "OpiumSec_Small", cx, py + 42, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        end

        -- Indicateur du groupe en cours (stage 1)
        if self:GetStage() == 1 then
            local panelW, panelH = 280, 36
            local px = sw - panelW - 20
            local py = sh / 2 - panelH / 2

            draw.RoundedBox(6, px, py, panelW, panelH, ColorAlpha(colors.Background, 220))
            surface.SetDrawColor(colors.Success)
            surface.DrawRect(px, py, 4, panelH)

            draw.SimpleText("Groupe en cours...", "OpiumSec_Body", px + 14, py + panelH / 2, colors.Success, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- ============================================================================
    -- PANNEAU DE CONFIGURATION (Menu Q -> Outils)
    -- ============================================================================

    function TOOL.BuildCPanel(CPanel)
        CPanel:AddControl("Header", {
            Description = "Relie les caméras de sécurité en groupes.\n\nClic gauche : ajouter au groupe\nClic droit : retirer du groupe\nRechargement : nouveau groupe"
        })

        CPanel:AddControl("TextBox", {
            Label = "Nom du groupe",
            Command = "opium_camera_link_group",
            MaxLength = 32,
        })

        CPanel:Help("Laissez vide pour un nom automatique (GRP-1, GRP-2...)")

        -- Liste des groupes existants
        local listLabel = vgui.Create("DLabel", CPanel)
        listLabel:SetText("Groupes existants :")
        listLabel:SetFont("DermaDefaultBold")
        listLabel:SetTextColor(Color(200, 200, 200))
        listLabel:SizeToContents()
        CPanel:AddItem(listLabel)

        local listView = vgui.Create("DListView", CPanel)
        listView:SetTall(200)
        listView:AddColumn("Groupe")
        listView:AddColumn("Caméras")
        CPanel:AddItem(listView)

        -- Remplir la liste
        local function RefreshGroupList()
            listView:Clear()
            local groups = {}

            for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
                if IsValid(cam) then
                    local g = cam:GetCamGroup()
                    if g and g ~= "" then
                        groups[g] = (groups[g] or 0) + 1
                    end
                end
            end

            for name, count in pairs(groups) do
                listView:AddLine(name, count)
            end
        end

        RefreshGroupList()

        -- Bouton de rafraîchissement
        local btnRefresh = vgui.Create("DButton", CPanel)
        btnRefresh:SetText("Rafraîchir la liste")
        btnRefresh:SetTall(28)
        btnRefresh.DoClick = function()
            RefreshGroupList()
        end
        CPanel:AddItem(btnRefresh)

        -- Clic sur un groupe pour remplir le champ
        listView.OnRowSelected = function(_, _, row)
            local groupName = row:GetColumnText(1)
            RunConsoleCommand("opium_camera_link_group", groupName)
        end
    end
end
