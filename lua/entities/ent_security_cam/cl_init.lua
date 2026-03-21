--[[
    Opium Security - Entité Caméra de Sécurité (Client)
]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    -- Afficher le nom de la caméra au-dessus
    local pos = self:GetPos() + self:GetUp() * 12
    local ang = LocalPlayer():EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    cam.Start3D2D(pos, ang, 0.1)
        local status = self:GetCamActive() and "EN LIGNE" or "HORS LIGNE"
        local statusColor = self:GetCamActive()
            and OpiumSecurity.Config.Colors.Success
            or OpiumSecurity.Config.Colors.Danger
        local group = self:GetCamGroup()

        draw.SimpleText(
            self:GetCamName(),
            "DermaDefaultBold",
            0, 0, OpiumSecurity.Config.Colors.Text,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
        draw.SimpleText(
            status,
            "DermaDefault",
            0, 16, statusColor,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
        )
        if group and group ~= "" then
            draw.SimpleText(
                OpiumSecurity.GetGroupName(group),
                "DermaDefault",
                0, 32, OpiumSecurity.Config.Colors.Accent,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
            )
        end
    cam.End3D2D()
end
