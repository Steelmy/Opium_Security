--[[
    Opium Security - Entité Moniteur de Sécurité (Client)
    Affiche le nom du groupe et le statut au-dessus du moniteur.
]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    -- Afficher les infos au-dessus du moniteur
    local pos = self:GetPos() + self:GetUp() * 18
    local ang = LocalPlayer():EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    cam.Start3D2D(pos, ang, 0.1)
        local group = self:GetMonitorGroup()
        local colors = OpiumSecurity.Config.Colors

        draw.SimpleText(
            "Moniteur de Sécurité",
            "DermaDefaultBold",
            0, 0, colors.Text,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )

        if group and group ~= "" then
            -- Compter les caméras actives dans le groupe
            local camCount = 0
            for _, c in ipairs(ents.FindByClass("ent_security_cam")) do
                if IsValid(c) and c:GetCamGroup() == group and c:GetCamActive() then
                    camCount = camCount + 1
                end
            end

            draw.SimpleText(
                OpiumSecurity.GetGroupName(group),
                "DermaDefault",
                0, 16, colors.Accent,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
            )
            draw.SimpleText(
                camCount .. " caméra(s)",
                "DermaDefault",
                0, 32, colors.TextDim,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
            )
        else
            draw.SimpleText(
                "Aucun groupe",
                "DermaDefault",
                0, 16, Color(255, 80, 80),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
            )
            draw.SimpleText(
                "Utilisez l'outil de liaison",
                "DermaDefault",
                0, 32, colors.TextDim,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
            )
        end
    cam.End3D2D()
end
