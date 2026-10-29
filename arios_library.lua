--!nocheck
--[[
	SINGULARITY  //  event horizon interface for Roblox                    v2.0
	-------------------------------------------------------------------------
	Floating glass panels over a live, ray-marched black hole. Every callback is
	an empty hook you fill in yourself - no features are wired up.

	QUICK START
		local Singularity = loadstring(readfile("Singularity.lua"))()

		Singularity:Load({ Title = "Singularity", Duration = 4.5 })          -- loading screen

		local Window = Singularity:CreateWindow({ Title = "Singularity", Width = 780, Height = 480 })
		local Tab = Window:CreateTab("Combat", { Icon = "crosshair" })       -- icon-only floating rail
		local Sec = Tab:CreateSection("Aim Assist", "Left")                  -- "Left" | "Right"

		Sec:Toggle({ Name = "Enabled", Default = false, Flag = "aim_on", Callback = function(v) end })
		Sec:Slider({ Name = "FOV", Min = 10, Max = 360, Default = 90, Suffix = " deg", Callback = function(v) end })
		Sec:Dropdown({ Name = "Part", Options = { "Head", "Torso" }, Default = "Head", Callback = function(v) end })
		Sec:Dropdown({ Name = "Checks", Options = { "Team", "Wall" }, Multi = true, Callback = function(t) end })
		Sec:Keybind({ Name = "Hold key", Default = Enum.KeyCode.E, Mode = "Hold", Callback = function(active) end })
		Sec:ColorPicker({ Name = "Color", Default = Color3.fromRGB(255, 132, 38), Callback = function(c) end })
		Sec:Textbox({ Name = "Name", Placeholder = "type...", Callback = function(text) end })
		Sec:Button({ Name = "Run", Callback = function() end })
		Sec:Label("some text")   Sec:Divider()

		Singularity:Notify({ Title = "Hi", Content = "Loaded.", Type = "Success" })

	CUSTOMISE
		Singularity:Load({ Title = "Hub name", Subtitle = "line under it" })  -- loading screen name
		local Window = Singularity:CreateWindow({ Title = "Hub name", ToggleIcon = "rbxassetid://0",
												  Watermark = true, WatermarkText = "Hub name" })
		Window:SetTitle("New name")   Window:SetToggleIcon("rbxassetid://0")   Window:SetWatermark(false)
		The "Made using Arios | Salfury scripts" line under the loading-screen name is permanent.

	LAYOUT
		Main panel (centered, drag to move, grip in the corner to resize) with a floating
		icon rail beside it (tabs live only in the Main section), and a floating section bar
		above it: Main | Settings | Keybind Manager | Config Manager. Switching sections
		slides whole panels sideways. The dock icon on the bottom edge zooms out to all four panels; click one to zoom into it. Window:SetSection("Settings") does the same from code.

	Values live in Singularity.Flags[flag]; elements in Singularity.Elements[flag]
	(call :Set(value) / :Get() on them).

	SOUND    Singularity.Sfx.Enabled / .Volume (0-1), Singularity:PlaySound("click").
	ICONS    CreateTab("Name", { Icon = "lucide-name" }). Known names get one automatically.
	QUALITY  Singularity:SetQuality("Ultra" | "High" | "Balanced" | "Low")  (also in Settings)
]]

-- re-execute safety: tear down any previous copy
local env = (getgenv and getgenv()) or _G
if env.__Singularity and env.__Singularity.Unload then
	pcall(function() env.__Singularity:Unload() end)
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local Singularity = {
	Version = "2.0.0",
	Flags = {},
	Elements = {},
	Folder = "Singularity",
	Notifications = true,
	Quality = "High",
	Accent = Color3.fromRGB(255, 132, 38),
	Windows = {},
}
env.__Singularity = Singularity

------------------------------------------------------------------------
-- registries / theme
------------------------------------------------------------------------
local Connections, Cleanups, Guis, AccentBinds = {}, {}, {}, {}
local TweenReg = setmetatable({}, { __mode = "k" })

-- Palette. Warm plasma (the accent) against cold starlight (Frost): the two colours
-- of the scene, redshift and blueshift, carry the whole interface.
local Theme = {
	Void = Color3.fromRGB(3, 4, 9),
	Panel = Color3.fromRGB(9, 11, 19),
	Glass = Color3.fromRGB(12, 15, 26),
	Raised = Color3.fromRGB(17, 20, 32),
	Track = Color3.fromRGB(10, 12, 21),
	Hover = Color3.fromRGB(30, 34, 52),
	Line = Color3.fromRGB(44, 50, 74),
	Frost = Color3.fromRGB(206, 222, 255),
	Text = Color3.fromRGB(240, 237, 232),
	Dim = Color3.fromRGB(150, 155, 176),
	Soft = Color3.fromRGB(118, 124, 148),
	Faint = Color3.fromRGB(88, 93, 114),
	Accent = Singularity.Accent,
	Hot = Singularity.Accent:Lerp(Color3.new(1, 1, 1), 0.68),
	Deep = Singularity.Accent:Lerp(Color3.new(0, 0, 0), 0.5),
}

local function ti(t, style, dir)
	return TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out)
end
local EASE = {
	Instant = TweenInfo.new(0),
	Fast = ti(0.14, Enum.EasingStyle.Quad),
	Drag = ti(0.07, Enum.EasingStyle.Quad),
	Med = ti(0.24),
	Slow = ti(0.5),
	Pop = ti(0.32, Enum.EasingStyle.Back),
	Leave = ti(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Rise = ti(0.5, Enum.EasingStyle.Quint),
	Slide = ti(0.42, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
	Depth = ti(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
}

local function loadFont(path, weight, fallback)
	local ok, f = pcall(function() return Font.new(path, weight, Enum.FontStyle.Normal) end)
	if ok and f then return f end
	return Font.fromEnum(fallback)
end
local Fonts = {
	Body = loadFont("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium, Enum.Font.GothamMedium),
	Semi = loadFont("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold, Enum.Font.GothamMedium),
	Bold = loadFont("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold, Enum.Font.GothamBold),
	Heavy = loadFont("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold, Enum.Font.GothamBlack),
	Mono = loadFont("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular, Enum.Font.Code),
	Display = Font.fromEnum(Enum.Font.Michroma), -- wide techno face, used for the wordmark only
}

------------------------------------------------------------------------
-- core helpers
------------------------------------------------------------------------
local function connect(signal, fn)
	local c = signal:Connect(fn)
	Connections[#Connections + 1] = c
	return c
end

local function safe(cb, ...)
	if type(cb) ~= "function" then return end
	local ok, err = pcall(cb, ...)
	if not ok then warn("[Singularity] callback error: " .. tostring(err)) end
end

local function tween(inst, info, props)
	local reg = TweenReg[inst]
	if not reg then
		reg = {}
		TweenReg[inst] = reg
	end
	local names = {}
	for k in pairs(props) do names[#names + 1] = k end
	table.sort(names)
	local key = table.concat(names, ",")
	if reg[key] then reg[key]:Cancel() end
	local t = TweenService:Create(inst, info, props)
	reg[key] = t
	t:Play()
	return t
end

local function cancelTweens(inst)
	local reg = TweenReg[inst]
	if reg then
		for _, t in pairs(reg) do pcall(function() t:Cancel() end) end
		TweenReg[inst] = nil
	end
end

local function onAccent(fn)
	AccentBinds[#AccentBinds + 1] = fn
	fn(Theme.Accent, Theme.Hot, Theme.Deep)
end

function Singularity:SetAccent(c)
	Theme.Accent = c
	Theme.Hot = c:Lerp(Color3.new(1, 1, 1), 0.68)
	Theme.Deep = c:Lerp(Color3.new(0, 0, 0), 0.5)
	self.Accent = c
	for _, fn in ipairs(AccentBinds) do
		pcall(fn, Theme.Accent, Theme.Hot, Theme.Deep)
	end
end


------------------------------------------------------------------------
-- sound design: UI sounds synthesized offline, embedded as base64 WAVs.
-- On first run they are written to <Folder>/sfx and played through
-- getcustomasset. Without file access they fall back to built-in client sounds.
-- Singularity.Sfx.Enabled / .Volume (0-1) control everything.
------------------------------------------------------------------------
local SoundService = game:GetService("SoundService")

local SFX_VERSION = "1"
local SFX_DATA = {
	["hover"] = "UklGRowFAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YWgFAAAAAIgBPwLb/s77yPyK/y4D0wdOBn/5Je9R+acO7hIcAWPxs/LT+ysFKhDbEe77cuEQ6b0PCCRsDUbtIudv9HUDWxM5GxgG1eDC27sDZia4GT31uuWu7+L+2g1hGYsOdey72sr1fh33HywA5uhJ7IX6zwjiFYAT3/dd3kTr/xGfIYgKrO526mf2OQSaEWIVuAFD5fvkzgXpHusSU/aq6sXyAAAhDd4UNwnj7QLjpPqrGFMY1P4R7QDwEvzKCLgSGA7M9s/kzvEmEEMaBQd68YPuefi1BKAPgxDd/m3pEezGBssY1g1h953uYvXoABkM4hBYBbnvounk/XoUdhID/mzwEPNm/XgIvQ/nCZj2OOqP9jQOdxSBBM3zzfE++u8EmQ2IDBz9L+158QgH0xMKCl74zvGT95UB5Ap1DZkCtvHk7gAA5RD4DY79J/OX9X3+8AcIDbYG8va07vr5TgzqD7YCvfV89Ln78gSjC1YJI/x/8I/12AbODzUHR/ln9Gj5DAKgCZIKtgCu8wfzTwHdDYYKWf1j9a73Wf9GB6QKUwSe92DyZ/yIClcMcwFc97D27/zLBNEJzwa1+1nzoPhlBpAMGgUb+of26vpUAl4ILwh4/4j1QvYPAlIL4wdO/Tv3ZvkAAIoGlAiSAnT4WvUX/u4IigmTALv4f/jo/YUELAjYBKT7xPXn+s8F9QmKA9v6R/gl/HQCLQc+BrH+N/fC+G8CNQnfBV/9wvjP+ngAyQXUBlEBWvm/9z7/ggdYB/v/4/n8+av+KwS5BlcDzvvK95T8LAXdB2MCiPu4+SP9dwITBrAEQf61+K/6jgJ1B1UEgv0I+vb7ygALBV8FcQA9+qf5AABFBqIFl//e+jT7Qf/GA3gFNAIc/Hf5zf2IBDEGigEj/On67f1iAhYFdAMN/gH6J/yDAgQGKQOw/Rf75Pz+AFgELQTb/xT7Kft7ADQFSwRZ/7T7NPyw/1wDZwRdAXz81/qt/uwD2wTuAKz85fuM/j8CNwR+AgP+HPtD/V8C1QRGAuT9+fuk/RkBswM0A3v/2PtZ/MMATARBAzb/afwE/QAA9AKCA8EA4/z0+0r/XAPKA34AJv20/Af/EgJ2A8ABE/4L/Bj+LQLeA5sBGf62/D3+IQEfA2wCQ/+H/EX96QCHA3ICJv8E/a39NwCQAsQCUwBK/dr8t//aAvICLwCS/V79Zf/fAdACMAE0/tP8t/70ARUDGwFO/lP9tf4dAZsCzgEn/yD9/P32AOIC0gEk/4b9Nf5bADQCKQIHAKz9kv0AAGcCRwL6//D96f2q/6sBRALEAF7+eP0r/7oBcgK8AIL+1f0T/xABKAJSAR7/o/2J/vQAWAJXASr/9f2i/nEA3wGqAdb/Bv4k/i4AAgLAAdf/Qv5b/t3/dwHPAXUAjP7//X//gQHvAXYAtP5G/l//9gC3AegALP8s/gP/2QDEAeYAR/94/hH/bwBpASABwP+M/sf+QABuASIBy//H/u/+AAAKASkBMAD7/sH+yv8DAS0BMwAk//L+r/+qAA8BegBo/+L+e/+XABEBewCB/xH/ff9UAN8AoADG/xz/VP84ANwAnwDT/0P/aP8OAKQApgALAGD/UP/x/5sApAAQAH3/a//e/2kAlQA4AKL/Zf/D/1sAkgA4ALT/gP/C/zUAdwBMANj/iP+w/yUAcQBKAOL/oP+5/w4AVABNAP7/sP+x/wAASwBHAAEAw//B//b/MAA9ABEA1//F/+7/JQA1ABEA4//U/+7/FAAnABUA8f/c/+v/DQAfABEA9//o//H/BAATAA8A/v/w//P/AQAMAAoAAAD4//n/AAAFAAUAAAD+//7/AAAAAAAA",
	["click"] = "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",
	["toggle_on"] = "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",
	["toggle_off"] = "UklGRmoSAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YUYSAAAAAHIArAFWA/UEAwYKBr8EGAJR/uf5jfUL8h7wWPD88vL3vf6JBkIOvhTlGOEZRhclERcIMP3b8a7nMOCe3LrdieTz7pL7uAiqFNQdAiOKI18fEhfCC/H+UfKN5xHg1txE3ibkse2c+VIGJhKGGzkhgSI4H9IXTg0TAcL0+ukn4k/e7t7t45zs0vcPBLcPPhllH18h7R5nGK4OEAMX91fsPeTX37bf2uOy6zH27wFgDQAXix0nIIAe0xjkD+QETPmj7lDmbOGY4Ozj8+q69PT/IwvNFK0b3R71HRkZ8BCSBmP72/Bf6AzjkuEg5Frqa/Mb/v8IqBLOGYQdTx06GdQRGgha/f7yZuqy5KDic+To6UPyZfz2BpEQ8BceHI8cORmSEn0JMv8M9WTsXebA4+LkmelB8dP6CQWLDhYWrRq5GxkZKxO7CugAA/dX7gvo8ORs5WzpY/Bj+TgDlwxBFDUZzxrcGKIT1QuAAuH4PfC46SzmDeZd6ajvFfiDAbYKcxK4F9UZhRj4E80M+AOo+hXyY+ty58TmbekP7+j27P/pCK8QOBbLGBQYLxSkDVEFVfze8wrtwOiN55fple7b9XH+MQf1DrcUtReOF0kUWg6MBun9lvWs7hTqZ+ja6Tru7vQS/Y8FRw02E5UW8xZIFPIOqAdk/zz3RvBr60/pNer77R/0z/sDBKcLuRFsFUcWLhRtD6cIwwDQ+NfxxexD6qTq1+1t86f6jQIVCkAQPhSKFfwTzA+JCQsCUPpd8x7uQesm68zt2PKb+S8BkwjNDgsTwBS1ExAQUAo5A7372fR170jsuevZ7V3yqvjo/yEHYQ3WEeoTWhM8EPwKTQQW/Uf2yvBV7Vvs/O388dP3t/6/Bf4LoBAKE+4SURCOC0oFWv6p9xnyZu4L7TLus/EU9579cASlCmsPIhJxEk8QCAwuBor//Phj83rvxe177oHxb/aa/DIDVgk4DjQR5hE6EGoM+gakAED6pfSQ8Iru1e5l8eD1rvsGAhQICQ1BEE4RERC2DK8HqwF1+9/1pvFX7z7vXfFp9df67ADdBt8LSg+rENcP7AxPCJ0CmvwQ97ryKvC172jxB/UV+ub/tAW7ClEO/w+ODw8N2Ah7A6/9NvjL8wLxOPCE8bn0aPny/pgEnglYDUsPNg8fDU0JRQSz/lL52fTe8cXwsPF/9ND4EP6KA4gIYAyQDtIOHQ2vCfwEp/9j+uL1vPJb8evxV/RL+ED9iwJ7B2kL0A1iDgsN/QmgBYkAZ/vl9pzz+vE08kH02feC/JoBeAZ1Cg0N5w3qDDoKMgZcAV/84fd79J7yifI79Hr31fu4AH8FhglGDGQNvAxlCrEGHwJK/db4WfVI8+jyRPQr9zr75v+QBJsIfgvaDIAMgQofB9ECKf7D+TX29vNS81v07faw+iL/rAO2B7YKSAw6DI0KfQdzA/r+p/oO96f0xPN/9L/2Nvpt/tMC1wbuCbIL6AuLCssHBgS9/4L74/da9T30r/Sf9sv5xv0GAv8FKAkYC44LfQoKCIkEcwBT/LP4Dva89On0jvZw+S39RQEuBWQIegosC2IKOgj+BBwBGv19+cH2QfUu9Yn2I/mj/JAAZgSjB9sJwgo8Cl0IZAW4Adf9Qvp098r1e/WR9uX4Jvzn/6YD5wY6CVIKDApyCLwFRwKJ/gD7JfhW9tD1o/az+Lj7Sv/vAi4GmQjeCdMJfAgHBskCMf+4+9P45PYs9sH2jvhW+7j+QQJ7BfgHZQmSCXsIRgY/A87/Z/x++XT3jfbn9nX4APsy/p0BzgRZB+gISQluCHgGqANgAA/9JfoE+PT2F/dn+Lf6uP0BASYEuwZqCPkIWQieBgYE6ACv/cj6lPhe9073ZPh6+kn9cACFAyAG6QekCDoIugZYBGUBR/5m+yT5zfeM92r4SPrl/On/6wKJBWgHSggTCMsGngTYAdb+//uy+T340fd5+CD6jPxq/1gC9QTmBuwH5QfTBtoEQAJd/5L8Pvqw+Br4kfgD+j789f7NAWUEZQaLB7AH0QYMBZ4C2/8f/cj6I/lp+LD47/n5+4r+SAHZA+UFJwd2B8cGNAXzAlAApv1O+5f5vPjX+OT5v/so/swAUwNmBcEGNge2BlMFPgO9ACf+0fuCC+cZdiUrLakwOzCpLAInTyBYGX0SswubBL38vvOl6fPerNQyzALHZ8Ysy13VM+Ql9iIJ6hpsKSEzSjcENjQwTSf4HMISzAmjAjf9+fgc9dvwu+u85WXfrtnG1dPUo9d53vLoCPZHBAwSzR1jJjcrTCwuKr4l+B+zGXITUw0dB2MAwPgI8H7m2tw81P3Nact2zYHULuBl73QAWREWIAUrIjEsMqUuqye0HjsVeQwvBY3/QPui9/XzqO+F6tLkRt/l2sTYyNlp3pDmjvE1/hMLsBbUH7glJChjJygkVR/EGREUfw77CC4Ds/xB9eXsFeSw2+DU4NC80A7V0t1U6kX56AhkFwwjqyqzLUwsQCfFHzoX3g6UB8MBVv3P+Yj25fKM7orpWuTO3+HcftxA30/lRu5B+QQFNRCYGUcg1SNVJEcibB6UGWoUUg9aCkoFxP9z+TvyWupx4nXbhdax1LrW4tzO5orzpwF8D2gbGCTFKEgpGSYsILYY7RDJCd0DSf+++7T4kfXm8ZTt3uhl5P/gkN/K4AHlEuxd9eL/agrFE/oadB8TISIgPx0mGYgU3w9ZC9wGHQLF/Jr2sO9u6JXhH9wQ2T/ZId2n5DDvnPt5CEIUmx2RI7wlTCTvH6kZmhLEC9cFHgGA/ZH6yfet9P/w0uyW6Pzk0+LW4nnlz+p28qj7WQVvDukVFxusHcUd1BuAGHIUMxAODAUI5ANZ/yD6JfSj7SfngeGe3V3cVN6x4xzswfZrArsNWxc/Hs0h8CEYHxIa3xN6DakH2wIg/zX8pvn69tvzOvBX7L7oIeY45YzmWepz8Ev4BQGhCScR0RYxGjkbMhqjFywUWRCKDN0INwVTAen8zvcV8hzsieYr4trfQeC54yvqB/NY/eoHfRH4GJ0dIh+4HfUZtRTjDkwJewSmALD9Pvvi+Dz2H/Om7zPsXOnL5xPojeo57731bP1mBcIMtBKzFosYXhiUFrcTVRDYDHkJMgbSAhX/wvrO9W/wIOuQ5oXjsuKQ5DfpWPA8+d4CGwzeE1AZ/hvhG1sZHBX3D7gK+wUVAgz/o/x8+jT4jvWD8lHvbuxw6urpR+us7uzzh/rCAckI0Q5CE8gVYhZVFRcTKhABDeUJ6QbwA78AGf3e+CL0Ou+w6jbneeUF5hrpnO4N9pz+SQcNDwcVohiqGU8YFhWyEOYLVgdsA08A4/3Z+9j5lvf29BPyRu8M7fHrZ+yv7sLyS/i0/kIFNgvsD/0SRxTuE00S2g8IDS0KbgfEBAIC7v5Y+z730PJ47svqbOjt56rpsu268yP7FQOeCt0QKRUpF+EWqRQUEdEMhAipBH8BBv8I/Tf7R/kH93v03PGN7wzuz+0n7yryq/Y4/DMC7AfBDDgQFxJjElwRZw/xDFYKzQdgBfQCVABQ/c755PXc8S3uaush6sLqe+0u8mz4hP+hBusMrxF4FCMV3xMdEXQNgQnHBZoCEwAW/mL8rvrD+I32KfTk8SjwZe/47w3ylvVG+p3//QTLCYYN3A+8EEgQ0g68DGQKDQjSBacDZQHb/uL7fPjW9ErxVe5/7D3s1+1S8Wr2l/whA0UJSg6rESYTwxLSEM4NRwrCBp8DDgEK/2T93Ps1+k74LfYH9DHyE/EJ8VPy+/TV+H39bQIVB/EKow0BDxYPHQ5rDFoKNQgkBiwEMgIJAIr9ovpl9xb0GvHq7vztpu4L8Qz1R/olAPkFEAvaDv0QZBE7EOAN1AqVB4sE9wHq/0f+2/xp+8j57Pfy9Rz0xfJG8ufyyPTX9877PQClBIUIdQs6DcsNSw3+CzkKRwhdBo0EygLwANb+YPyP+Y72qfNK8eHvy+9B8UD0i/iv/REDEAgXDL0O0A9gD68NJgs8CFsFzgK5ABT/tv1r/AT7aPmi9+H1bPSa87Xz6/RA94j6bv6AAkgGXAlyC20MXgx3CwEKRwiCBtMEOgOdAdb/xP1b+6/4+PWN89TxK/HY8fHzWPe4+5MAVgVzCXUMFw5NDj4NPwu1CAoGkQN5Ac//dv5F/Qz8qvoa+Xn3//X39Kr0UfUA96L5+vyoAEMEYAewCQQLWwvXCrIJMwiXBgYFjQMdApgA3P7R/H36A/in9cLzrvK58gr0nfY7+oH+7QL8BjYKRwwNDZYMHwv/CJcGPQQrAnoAIv8A/uj8t/tc+uL4dPdO9rf16vUJ9xL53Psf/3gCiQX7B5cJSAohCk4JDQicBigFygN9AisBtP/9/f37yPmP95v1QfTN83b0S/Yu+db82AC9BA4IbwqsC78LzQobCf8GzwTLAhkBvv+i/qP9mfxt+x76xviX9872p/ZM98v4Dvvf/ewA3QNdBiwIKglYCdUI1QeSBj0F9gPDApgBWADp/jf9SftA+VX30vUC9SH1UPaF+JD7G/+9AggGnAg4CsIKTAoICUEHRQVZA6sBSwAy/0H+Vf1S/C779PnK+OT3eve898L4h/rm/J7/XwLaBMoGBgh/CEkIiwd6BkYFFQT4AukB1ACf/zP+ivy4+uf4VPdF9vr1m/Yz+KX6s/0BAS4E2Qa6CKkJpAnMCF0HngXTAy8CzwC0/8v+9P0T/RX8/frj+fD4WfhN+Oz4Pvou/Iz+EQF3A3gF4gacB60HMQdTBkMFKgQeAyUCMQEqAPr+kv35+0z6vviK9+/2HPcq+A36m/yM/4YCMQVAB34I3QhrCFUH2AU2BKQCRwEqAET/e/60/dn84vve+u35Ofny+D35Kvqy+7P99/85AjoEwwWzBgQHxgYdBjQFNAQ6A1ICdgGTAJT/Zf4F/YX7CPrE+PL3xfdc+L750Ptb/hUBqwPQBUsH/QfoByoH9AWCBAkDtAGWALD/7/47/n39pvy8+9X6FPqk+ar5Qfpq+xH9Df8iARYDsATJBVAGTQbZBRkFNgROA3QCqQHiAAkADf/i/ZD8MPvt+fn4h/i9+Kv5SPtt/dz/TAJ1BBgGDgdLB+AG8gW1BFwDFQL5ABIAVf+u/gb+TP19/Kb74/pY+iv6efpO+6D8Uv4zAA4CqwPhBJcFyQWIBfMELQRZA40C0AEcAWIAj/+U/nD9M/z9+vn5V/k/+cv5/fq9/Nv+GQE0A+0EFgaaBnsG1AXPBJwDaQJTAWsAsP8R/3n+2P0j/WD8o/sK+7j6zPpX+1v8xP1t/yQBugIBBNoEOwUrBcAEHARdA58C7QFIAaUA8/8h/yn+Ev3x++v6K/rY+RP65fpF/BD+EwASAtEDHgXaBf8FnAXRBMkDrgKjAb0AAQBn/9v+Tf6w/QL9Ufy0+0n7MPt++zv8Xv3M/lsA3wEsAx8EpwTDBIMEAARaA6oCAwJpAdcAPgCQ/7/+zf3I/Mv7+/p/+nf69/r/+3j9PP8TAckCKwQTBXMFTgW8BOED5ALoAQcBSwCy/y//r/4n/o797PxS/Nn7ovvC+0T8Jv1W/rT/FgFWAlED8AMuBBMEswMqA48C+AFuAe4AcADm/0P/hP6v/db8FvyO+137mPtD/Fb9s/4zAKkB6gLSA04EWwQHBGwDqQLcAR4BewD4/4r/J//B/lL+2f1f/fj8t/yx/PP8gP1R/k//XgBgATgC0AIeAyUD8AKTAiECrAE/AdwAfgAcAKz/Jv+N/ur9UP3V/JH8l/zy/J79jf6k/8EAxQGSAhMDQQMhA8MCPAKlARIBjwAkAM3/gf83/+n+lP49/u79tv2i/b79Dv6Q/jb/7/+kAEMBugEAAhUC/gHHAX4BMAHmAKMAZwAsAO3/ov9N/+/+k/5E/hD+BP4m/nf+8f6G/yMAuQA1AYkBsgGvAYcBRwH5AKsAZAAoAPr/0/+w/43/Z/8//xn/+v7q/u7+Cv88/4L/1P8mAHIArwDXAOgA5ADRALMAkQBvAFEANgAdAAQA6P/H/6P/ff9b/0L/N/8+/1f/gP+3//P/LQBgAIYAmwCgAJYAgQBlAEgALQAXAAQA9//r/9//1P/H/7v/sf+r/6r/sP++/9H/6P8AABcAKgA3AD4APgA5ADEAKAAfABYADwAJAAMA/v/3//D/6f/i/93/2//b/+D/5//w//r/AwALABAAFAAUABMAEAAMAAgABQACAAAAAAD///////////////8AAAAA",
	["tab"] = "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",
	["slider"] = "UklGRiwDAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YQgDAAAAAPsB1QFw+5b5wgOICw8BefEb90ANahEu+WLoDPzJGJ8P5+7D6AgGmRnrBZ7p1u9+DpEWN/wa6Kr4DxR7EPDzP+rHASwWgggt7mfv0QnUFAAAj+uM9rAPiRBB+DDscf65EjEKV/Ku79wFuhLpAvjuRPXAC/kP2/to7u/7Yg8cCwv2fvCaAmwQCwU38q30SgjzDsj+w/An+kAMaAtB+a/xAAAMDn8GOPWj9FMFng0SASLz//hkCTcL+fsh8wD+tQthB+33BvXZAhcMywJu9V742AapCjf+tvSJ/HkJyQdO+rr11wB5CgUElfcp+KME1gkAAFj2iftpB88HV/yk9kT/2AjQBIz5S/jEAtgIYAH19+76jQWLBwv+sfcU/kQHPwVM+634OgHCB2ECffmn+uoDEAdt/874Pf3JBWMF0fw9+QAAowYRA+j6ovqEAm4GgQDs+bH8bwRMBRn+7PkP/4cFfAMw/NH6WAG2BVIBAvtl/DsDCQUo/6v6Xf55BK0DT/0m+2UA8gTmAQb8TPwwAqUEAABx++T9gAOwA0b+lfun/y0ERgL0/Fz8TgEtBKYAM/yb/Z8CkAMU/xT8GP9uA3oCyP2L/JQAqgMgAfL8gv3QAUADvf+7/MH+mAJmApf+B/0AAOACUgHT/bn9DwGxAjUAfv2l/s4BJAI9/5X9of8rAlsBh/4E/oMAJwJ+ACb+rP4uAdMBs/8a/mz/kQFHARP/WP4iAKkBoQCx/sv+tQB9AQAAkf5Y/xQBIQF6/63+5v86AakAIP/3/l4AKgEtAPf+W/+zAPEAw//9/sX/3QCeAHT/Kf8jAN4AQwBK/2z/agC+APH/RP+5/5MAhwCx/1v/AACdAEcAi/+H/zgAjAAKAID/vP9aAGoA2/+L/+//ZwA/ALz/pf8XAGAAFQCw/8f/MQBLAPT/tP/q/z0AMADe/8P/BAA5ABUA1v/a/xUALAAAANn/7/8bABsA9P/j//7/GAAMAPH/7/8FABEAAgDz//n/BwAJAP7/+f///wQAAgD/////AAAAAA==",
	["select"] = "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",
	["dd_open"] = "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",
	["dd_close"] = "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",
	["open"] = "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",
	["close"] = "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",
	["notify_info"] = "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tgD/AAAB0QCOAFAADQCk/zT/Av8P/0L/f/+4/wQAewDbAPkA4QCtAHcAPgDh/2j/Hf8R/zD/Yf+S/9L/PwCvAOUA5ADBAJQAZgAYAKH/Qf8d/yf/S/9z/6X/BAB8AMkA3wDOAK0AiABLANz/bf8y/yf/O/9Z/37/zf9EAKQA0ADTAL8ApAB3ABUAn/9Q/zD/M/9F/17/mv8LAHgAuADPAMoAuwCdAE0A1v92/0H/Mv83/0T/bv/S/0YAmQDDAM8AywC7AH8ADQCi/1v/OP8v/zH/Sf+b/xEAcwCvAMwA1QDTAKwARgDT/3z/R/8u/yT/K/9o/9r/RgCUAMIA2QDkANAAfQAHAKT/Xv81/x3/Fv88/6L/FQBxALAA1gDuAO0ArwA+AND/e/9B/xz/Bv8X/2z/4/9KAJoA0AD0AAQB3AB0AP//m/9R/x7/+/74/jr/rv8gAH4AwwD1ABQBAgGpADEAwv9p/yf/9/7i/g3/eP/x/1sAsADvABwBIQHbAGYA7v+G/zf//f7a/vD+T//J/zsAmADfABIBJQHxAIMACgCh/03/Dv/j/uf+Nv+r/x4AgADLAAMBIQEBAZ8AKAC8/2P/IP/v/uT+IP+P/wIAZwC2APIAGgENAbgARQDX/3v/M//+/uX+Dv90/+b/TQChAOEADwETAc4AYADy/5P/R/8N/+v+Af9a/8r/MwCKAM4AAgEUAeIAewANAKv/XP8e//T++P5D/6//GQBzALsA8wAQAfEAlQAnAMT/cf8w/wD/9f4v/5X///9cAKcA4gAJAfsArABCAN3/h/9D/w7/9v4e/3z/5v9EAJMA0QD/AAEBwQBbAPb/nv9W/x3/+/4S/2X/zP8sAH4AvwDyAAMB0wB0AA4AtP9q/y7/BP8J/1D/s/8UAGgArQDjAAAB4QCLACcAzP9+/z//D/8F/z3/m//9/1IAmgDUAPkA6wChAD8A4/+T/1H/HP8G/y3/hP/l/zwAhgDCAO8A8ACzAFYA+f+o/2X/Lf8N/yT/cf/P/yYAcQCvAN8A7gDAAGkADgC9/3n/QP8Z/x//Yf+7/xEAXQCbAM4A6QDKAHsAIgDR/43/U/8m/x//U/+o////SQCIAL0A3wDQAIwANQDl/6D/Zv82/yL/SP+X/+z/NgB1AKsA0wDTAJoARwD3/7L/eP9G/yn/QP+H/9r/JABjAJkAxQDSAKYAWAAIAMT/if9X/zP/PP95/8j/EgBSAIgAtgDNAK8AZwAZANX/mv9o/0D/O/9s/7j/AgBCAHcApwDFALUAdgApAOT/qv94/03/Pf9i/6r/9P80AGkAmQC9ALkAggA3APL/t/+F/1n/Qf9Z/5z/5v8nAF0AjACzALoAjgBGAP//w/+R/2X/R/9T/47/2P8aAFEAfwCoALkAmABUAAwAz/+d/3H/Tv9P/4L/yv8NAEUAdACdALUAoABhABkA2/+o/33/WP9O/3b/vP8BADoAaQCSALAApgBuACcA5/+z/4j/Yf9Q/23/r//1/y8AXgCHAKgAqgB7ADQA8/+9/5L/bP9T/2X/of/o/yQAVAB9AKAAqwCGAEIA///H/5z/dv9Z/1//lP/b/xkASwBzAJcAqQCPAFAACgDS/6X/f/9g/1z/iP/N/w0AQQBqAI4ApgCXAF0AFwDc/67/iP9n/1v/ff+//wEANwBhAIQAoACcAGoAJgDp/7n/k/9x/17/dP+w//T/KwBWAHkAlwCdAHYANQD2/8T/nv98/2P/bv+j/+X/HwBLAG4AjwCeAIIARQAEAND/qP+F/2j/Z/+T/9T/EABAAGUAhwCdAI0AVgAUAN3/sv+O/27/Y/+E/8L/AQA0AFsAfgCaAJYAZwAmAOv/vf+Y/3b/Yv94/7H/8v8nAFEAdQCVAJsAdgA3APr/yf+i/37/ZP9u/6D/4f8ZAEYAawCOAJ4AgwBIAAkA1v+u/4v/bv9u/5b/0v8KADYAWgB6AI8AgQBQABYA5v/A/5//gv95/5X/yf/+/ygASQBmAH0AeQBTACAA8v/O/7H/lv+I/5n/xP/z/xsAOQBUAGoAbgBTACcA/f/c/8H/qf+Z/6D/wf/r/w8ALABDAFgAYABPACsABQDn/9D/u/+r/6v/w//m/wYAHwAzAEUAUABHACsADADy/93/zP+9/7n/yf/k////FAAlADQAPwA8ACkADwD6/+j/2//O/8j/0f/l//v/DAAZACUALgAvACMAEAD///H/5//e/9f/2//o//n/BQAQABgAHwAhABsADgABAPj/8f/r/+b/5//v//n/AQAIAA0AEQATABEACgACAP3/+f/2//T/9P/3//z/AAACAAQABgAGAAUAAwABAAAA/////wAAAAA=",
	["notify_success"] = "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",
	["notify_warn"] = "UklGRkopAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YSYpAAAAACUAsgC4ATkDNQUxB80HfAd8BuoE1AJAADP9rPms9TXxRuwi67vsu++W8xL4Ff2UAo0I/Q7kFUAdBSJlIOgb/hU7D9oH9v+W97/udOW124LRetHD1nHeWecD8UD7+gXREKYbeCZGMfk1LjGyKMkeVBSrCfH+MvRz6bjeANRnydjLXNPX3BTnmvE5/OAGiBEtHM8mbjHUNKUvHydPHQEThAj4/Wjz2OhM3sPTjcpszf7UYt556NPyRf29BzcSrRwhJ5ExtjMmLpcl4Bu4EWYHCP2l8kTo5t2M067L986V1uLf1OkD9En+kwjeEicdbSeuMZ0ysCwZJHsaeBBSBiD86/G354bdWdPJzHjQIthY4STrKvVD/2EJfxObHbMnyDGKMUQrpSIgGUMPRgVA+zfxMOct3SzT3s3v0aTZw+Jr7Ef2NAAnChkUCB70J9wxfTDgKTwhzxcXDkMEaPqL8LDm2NwE0+7OXdMc2yTkqO1c9x4B5QqrFG8eMCikMVkveyjYH4YW8wxIA5j55u825onc4NL4z8LUi9x75dzuaPgAApwLOBXRHmYomDDpLf8mcR5CFdYLVQLP+EfvwuVA3MHS/NAe1u/dyOYH8Gv52gJMDL4VLR+YKJIvgyyNJRQdBxTCCmoBDfiw7lTl/Nun0vzRctdK3wzoKfFm+qwD9gw+FoMfxSiQLiUrJSTBG9UStwmHAFP3Hu7s5LzbkNL20r3Ym+BH6ULyWft3BJgNuBbUH+4olC3QKcYidxqtEbQIrP+f9pPtieSC237S69MA2uPheepS80P8OwU0DiwXICASKZ0sgyhwITcZjRC5B9j+8/UO7SzkTNve0gXVS9sp46XrW/Qn/fgFyg6aF2cgMimsKz8nJCD/F3UPxgYL/kz1j+zT4xvb0dNT1qTcb+TL7F71BP6uBloPAxiqIE0pvyoCJuAe0BZmDtsFRf2t9BXsgOPu2sDUmdf03azl6e1Y9tn+XgfjD2cY5yBlKdYpziSlHaoVXw33BIf8E/Si6zLjxtqq1dfYPN/g5v/uS/en/wcIZxDFGCAheCnzKKEjcxyMFGAMGwTO+4DzM+vp4qLaj9YN2nrgC+gM8Db4bgCpCOUQHhlVIYgpFCh8IkgbdhNpC0UDHfvz8srqpOKB2nDXO9ux4S/pEvEa+S4BRgldEXMZhSEJKQQnSSEeGmUSdwp3AnL6a/Jm6mTiZdpM2GLc3+JK6g/y9vnoAd0J0RHCGbEhLCjXJR4gGxmiEQUKWAKN+qnys+qx4qPaPNlP3Xzjceqr8ff4kwB6CIsQtRjvIOQmxySOHycZVRJhCywEa/xR9Ajsp+M22y/a/92q4wTqmvA/97P+vgYaD54XOCC6JdYjEx8yGeMSagxrBZD9PPWx7BLkbNv52szeSORn6sXwPPe9/twGRw/OF2Ag/iTTIgUeMRj4EZoLoATZ/KL0OuzA4z/bqtvB30blV+ue8RL4gv+FB80PMRieIE4k2CH+HDcXFRHRCt0DKfwP9MnrcuO625bcyeBH5kTscvLj+D8AKAhPEI4Y1yChI+Mg/htDFjcQDQofA3/7gvNd6yrjZ9yR3dLhRuc47WDz6vlcAVIJbBGIGZshaiM8IBkbLBXtDokIRQFR+UbxU+l54e/bwd134lHooe4l9R388gMVDPkTqBs2I8Ej4B9AGu4TUg2VBuj+lPae7gjnq99w2/ndK+Np6Q/w2/Ym/jYGTg7hFSEdNySjIzgfUBnVEiIMVgWa/U/1nO1U5kLfBNzq3jHkZur08KT35v7gBscOLxZKHT8k5SI/HlMY6RFPC4kE4fzI9EDtHeYs38Pc6d845V3r0/Fo+KD/hAc6D3gWcB2PI+QhMh1SF/8QgArCAy78RvTp7OrlGd9+3ePgOOZN7KvyJflSACIIqQ++FpId1CLlICkcWBYcELgJAQOC+8rzluy65QnfNt7W4THnNu1989z5/wC6CBMQ/xaxHRwi6x8nG2QVPw/1CEcC2/pS80jsjuX93unew+Ij6BnuSfSN+qYBTAl4ED0XzB1oIfceKxp3FGgOOQiTATv64PL962bl896Z36rjD+n27g/1QvtNAtYJ1hB1F+QduCAJHjcZkBOYDYIH5ACh+XLyt+tA5f3eTOCO5PXpze/P9fz79QJRCikRpxf4HQogIR1IGLASzgzRBjwADPkK8nbrKOXE32zh1+VT6yTxDfcl/fQDAQuJEbMXqx3AHlMbIRZ0ELYK/QSw/t33WvFH63flOuF+40/o+O2k8zj5+f5dBeQL6RGXFxYdGR0aGYcT4w1rCBUDJv2/9sDwLevT5afibeWE6i3wnPXZ+k4AYAaBDC4SkBfPHAkcwhchEqoMbAdOAoL8P/Zz8AXrx+VU41LmbOv28Ef2avvYANkG1AxfEqYXzBxgG+sWWRH6C9QGwgEC/Nr1MvDi6r/l/+Mw503sufHt9vb7XAFOByMNjhK5F5wcqxoTFpQQTgtABjQBg/uI9Qzw6er15fvkauiJ7c3y0feo/OkBpgcqDUMSHRcJG8cYNBT0DvkJOwVyABP7g/Vt8KnrEufp5nzqce9c9AT5f/11At4H+QywESwWIRmmFjISRg2lCEIEwv+0+oj1y/BW7ATohegp7PHwjvXr+SL+6gIkCAENhRHZFRkYghUmEW8M/Qe+A0z/TfpD9aPwRuwI6Bfp4Oyk8Sf2a/qN/lADfAg6DaIR4BWGF8UUaBDMC3QHSwPd/ur5AvV+8DfsDuim6ZPtRvK09uT6AP+5A8wIaw27EeMV9RYMFK4PLwvvBtwCcv6L+cP0WvAq7FXoSupK7ujyPvda+3P/IQQTCZcN0BHkFWgWWBP6DpUKbwZwAgv+MPmI9DrwH+zw6AvrC++S89r38vsgAN4EuwkjDjwSKxYKFrUSMQ65CXcFVAGz/Mv3TPM572PrDumO69Hvg/T6+EX9twGWBkgLZw8tE8UW2hUbElENrAg7BOb/A/si9ufxJu6m6i7pF+ye8Hf1Evp+/hwD+gduDEQQwBMUF3sVcxGNDOQHdAMj/z36gPV+8e/tmOq46c7sV/EV9pb67P6DA0gIlwxRELoT/BbpFMMQ7wtbBwADtf7n+U31Z/Hu7ajqTOqF7QzyrvYV+1X/5wOTCL4MXRCyE5MWPBQMEE8L1AaOAkj+lPke9VXx8O276uLqQ+7V8m33zfsAAIoEFwkSDYYQsRPjFU0T/g43CqsFaQEw/ar4efTx8Mvt1uqp61rvGfTI+C79QgGoBfQJnw3KELITJBU+EsQN6ghHBBgA/fu299TzlPCx7fvqcexp8Er1APpV/kACfgaPCvcN6hClE3kUYhHcDBMIhAN6/3j7Wfen84nwve0X6//sEvHn9YX6vP6QAsMGvwoHDuUQjxPoE7IQMAyBBxMDJP8o+yD3j/OJ8M7tNeuK7bfxe/YD+x7/6QIEB98KDw7aEHcTWhMGEIgL9AanAtD+3Prq9nnzifDf7bLrN+5l8hD3f/t9/z8DQgf8ChQOzxBeE88SYA/kCmsGPgJ//pP6tvZk84vw8O1K7OruE/Oi9/j72v+SA34HFwsYDsIQRRNHEr0ORgrmBdgBMv5M+oX2UfOO8APu3eyZ77zzMPht/DIA4wO4BzALGw61ECoTwxEfDqwJZQV1Aeb9CfpW9kDzkvAW7mjtP/Bf9Ln43fyHAC8E7gdICxwOpxAQE0ERhg0gCe0EGQGc/cv5LPYx85fwKu7s7eDw//RG+VX99AChBFIIjgtIDroQChPJEOQMdwhABGkA1vwO+ZT1v/JL8AbuUu6B8cD1Evol/tABjAUiCSsMsw72EK8SLRAoDLMHcAOT/+b7Mfjo9ETy/u/m7bvuJfKA9tf65/6SAk0GwQmWDPEODRE3EokPeQsQB9oCEP9n+9T3tfQy8gXwAO47777yFPdT+0X/2gKHBuUJnQzkDvMQqRHkDtsKiwZtAr3+JPup96j0OvIb8CDuu+9T86X3zPuh/yADvwYGCqMM1w7ZECURRw5CCgsGBgJv/uT6gPed9ELyMfBA7jfw5PMn+Dv89/9mA/IGIQqmDMgOvhCmELANrwmPBacBJv6o+lr3k/RM8kfwa+608HP0pvim/EkAsAMiBzIKogy3DqIQKRAdDR8JFwVLAeD9b/o294r0VvJe8PPuU/EM9Sb5EP2aAPgDUAdCCp0MpA6FELAPjQyUCKIE8gCc/Tf6FPeD9GDydfB37+3xoPWj+Xf96AA8BHwHUAqXDJEOaBA5DwIMDQgxBJwAW/0C+vT2fPRr8o3w+O+D8jH2G/ra/TMBeQSjB1sKkAx+DksQxQ56C4sHxANJABz90PnV9nf0d/Kk8G/wEPO79pD6Nv55AbMExwdlCogMag4tEFUO+goeB3EDFwAC/c/57Pae9KXy0fDo8I7zIffK+jz+TwFxBHYHCgowDB8O3A/iDZsK7wZ0A1EAV/02+lv3BvX78hLxYfH882z34Poa/vkADgQQB6QJ1gvXDU0PXg05Cr4GbwN4AIv9dPqf90X1MfM98c7xbvTO9yX7P/4HARsEFweeCcgLxA3aDtcMtglQBhQDMgBJ/UX6ivdB9TrzUPE08uj0RfiI+4v+SAFUBD0HrQnGC7YNbA5VDDgJ5gW9AvD/Df0a+nb3P/VE82Txl/Je9bb46PvU/oUBigRiB7oJxAunDQcO2gu/CIAFbAKy/9X88fll9z71T/N58fjy0fW9/UwHQhFSG74lAjDKOf8/3j4jOQUwpiULG5EQaAYR/MDx0edF3vHU3ssoxkDCacfKzyzZ9eIg7ST3swD+CSYTNho8H4kj1idYLCcxti6gJx0fQBZQDdcEX//o+rH2TfKY7d3oRuRy3zDaE9kO3hvjXedm66fvMvQL+aL9UAJoB9EMYRLNGOwhGirCKj4oPCTPH08bexY7EcALLQYE/mX0SepV4KTWNc17y7PN2NHb1jvc2eLs6831yv+XCQwTkhwiJmcvSTiJO2k5aDJVKYgfyhVEDPACUvnd797mKN6U1W/Oh8lOyOHN5dWc3tfnPfFh+iwDyAtNFLwZBx71IQomYCpgLgUqrSKLGjISyQn+Aj7+Nvo89hfyqe1s6S7lm+C12wTdd+KZ5ljqC+798T/2lfq+/hcD2gfXDO8R9BjSIWUnKSd6JKYgshyRGAcUKg8kCpEEPvz18nDpE+AD14nPGs+u0bvVatpb34vmYe/M+CYCSgsrFEkdTSbrLj03JDieNDEtWSQbG+8RCQkZABf3Vu715crdutUb0OrLJM0z0/XaPuMS7OH0Uv1+BYkNdxQeGfMcoyBzJI4o+ykaJQ8eahaaDr0GewFx/dL5FPYb8vftGOoX5qvhVt1x4CTl6uhm7PXvuvPN98D7r//mA28IIg3nEYgZMCJiJU0kXyG0HQAaDBarEQwNUwgHAuL5FvFD6J3fPtdB0rTSk9WQ2QXe4uKD6hbz7fueBAwNaBXoHTYmIS57NA80PC+/J0gfsBY4Dv0Fj/0w9SntbeXY3dTWTdKnztPRPdix36bn5O//98X/WAfTDkMUPBiuGywf2SK9JvglrCDvGcUSeAvhBIIA7vyE+fz1L/Jw7sPq3uan4o3gNOTg5yjrUu638Vz1NPnO/IQAmATpCFUNyxJIGkgiXyOZIX4eDxuCF6cTeA8dC7AG0v/d94zvXOdm35nX0dQL1ifZEt1Q4ebmXe599q7+uQaADmUWRx7jJTEtKTEBMDwqySLCGsIS8go6A1b7mvM97BnlEd6H2KzUkNKu1gvdGOSn60/zt/raAdgIhA+7ExUXOxqIHRYhsSQsIqocRxaeD+AIwgMcAPf8uvlJ9pryGu+L66znjeNK48vmvumN7IbvyfJe9vn5gf06AUYFfgnKDfgTcBtGIX4hXB8tHOAYXRV9EVwNHgkaBBT9WfWd7Rbm3N631xHXLdmS3IPgrOT46mnyLvq8AQkJIxBwF54eziX7LGUvPy3fJ1Mhmhq/E4gM5QQU/W71C+7P5qXfwtrZ1gjWt9n73szkFetj8RH49/72BdoLHBDQE5MXiRvAH+IiPSCYG1gW5RBqC74HZQTzADD9IPny9Orwvew+6JLjROSQ5oTobeqc7GbvBfPS9sv6F/+mA1gIWQ2LFH0c7iAhIYAfNx3MGvwXNhTiD00LFAWE/Yb1q+0J5qTe4Ng/2ODZgdyK3znjkekN8c34cADaB0QPvhYHHgYl1Ct5LP0obyMqHe4WcxCmCWUCHfsV9EHtieaP4Gfc5diz2bjdy+Jo6ELuNPR6+u4AeAcjDNEPNxPMFpoakx7MH7scRBhXE40OwAoCCHoFvwLG/4X8HPkz9cjw+uvP5/HoEeoj61Ls0e0V8PTy5PUP+ZP8UgC5BJUKFBIkGjEdRx0KHHoavhhoFlAT0A8TDCIGcf8o+KrwNenB4Wbd79w33jTgduIz5uHrWPLe+EP/cwUODBYTHxoYIXQmziZcI4YeVhk7FMQO7QjMAr/86fYN8bbqg+Va4YLdFN+r4unmpOtw8Gb1sfosAEQFnghaC5MOVBJ/FrsaCRtYGKYUkxBbDH0JGAezBAICEP/s+5j4xfRz8OXrg+mF6oDrhezI7VDvtfFv9Ev3ZvrC/WsBnAXcCyATABq2G0Yb7xl7GNIWYBRWEf8NsQneA3/9nvaU75/oieHt3h/fk+CM4rvkL+nn7hP1MfskAf8Gag0ZFKoaIyGfJI8jyx8OGy0WSREMDGIGlgDz+oj1+u8i6v3laeJK4GLi9+Ui6qvuLPPv9+r8AAL4BcMIRwtgDu8R0xWlGXUYaxXLEfcNWQofCA8G1QNVAZT+yPuU+Of0yvB17JHrRuwT7f3tMu/T8CfzoPVK+ET7df4SApYG7AzqE+8Y+xlUGRsYtBYNFY8SlQ9iDJsH4wG4+0H1t+556L/i0uEA4xXliOfD6rnvLvWY+tb/1wTmCXgPKhXBGkMgpCHrHnIaZBVcEEALSQYwATT8hPcC8zbu5um75vLjvOOm5qDqKO/i85b4Nf2vARMGpwiMCoMMCg/8ESAV9hbRFFsRcQ1eCS4G7QMXAjsAPv4R/Oj5R/cw9MLwK+0E7hTvTfC48WnzjfW+98/5+vtk/vEA/QN3CCsORxQfFwkXsRULFDMS6w9iDcUK2wdbA1H+7/hX88HtG+gu5PHjVuVn573pbe1P8nb3dfxEAeUFzAoNEE4VexokH/weshs/F7USUw7xCZYFPAEO/R/5LvWK8NnsxOnZ5nnnOOq37bLxvPXE+aH9YgF7BEEGlwedCU4MdQ+wEpETjBGRDj4Lywe9BTwE8QKIAff/Sv5J/JT5SPau8gPwXPD/8Mzx2/Ik9Nv1fvcY+dj6y/wX/x8COAcYDSwT7hSqFJoTXxLwEAUP+AzfCuIH1QNd/0H60PRS76bp2+bV5gPorumq62vvxvMw+HD8fgB+BCMJOQ5cE3wY+hsdGwEYFxQREB4MGAj8A/P/JPyF+Kj0ffBl7aXqQOi86ZrsEPDO84T3PPvR/k4CmgQNBlkHdQkkDCsPJhLXEZsPsgyMCcAGBQXBA4UCLAGo/yT+CPxM+Rv2sfJS8YHxEPLV8ufzP/Xf9lf42/mU+6L9TAAxBJoJkA+lFBEWzBW2FEATexE/D+kMjQrLBmsCrf1s+PTybO2x59bl++VL5yfp8esP8I30/PhI/WQBngV8CqIPzhT3GX8cFRvpFwUU/w/nC8sHmQOD/6r78/fK8/nv2ezt6VfotulN7Lvve/Mz9/76sf4tAjwEzAWWBxcKFg1FECgTZxJVEH8NTQrpByAGnAQJA1cBgv+v/Sr7Efig9AjxKPAC8IPwgvHb8p/0a/Yo+P/5B/wu/vMARwWVCjcQ3hO3FC0UFhOnEdcPtg2EC+QIHgXxAGH8ZvdN8g/tq+jG54LoKOo57Kbv+PNj+HH8NQDNA6wHEAyXECMVrhk0GgQYfxSMEIcMbQhMBGsA1vyC+UP2e/Kb7xjto+pk6kPsLu/I8pD2V/oT/osBJQSwBdwGhAjCCmYNFxCMEUUQ4w3kCqEHoAXcA1AC3QBl/+z9SvwK+kf3Q/Rc8SPxePFZ8qvzRPU+9xf5ufpd/Bn++P+dAuQGxgvIEOwSBhMSEq4Q/A7cDJsKiAi3BTcCgv5d+uv1ZvGx7LbpZOlh6g/sU+7n8Qz2EfrH/TgBnQRfCIEMuRD2FIAY9RdyFf4RSw6VCsQG7AJc/xv8Dfnt9a/yKvDf7YXrM+xH7kbxtvQ1+MD7M/9dAkQEhAWdBlkIlwoeDZwPDhCUDiwMSQm0BuEETQPiAYoAJP/T/Rz81vkq90/0g/Iw8o7ydfPF9Ff2NPjb+V/79vyc/ocAlwPLB2oM5BAFErIRqRBCD5MNhgtuCX0HcAQGAX39hfla9RPxquzU6vLqH+zP7XDwD/Ty95L77/4VAkgF7QjQDMEQtRT1Fr4VDhO+D0gM0Ag1BbMBd/6Y++34CPaM84HxkO8b7lXvffFW9Gv3dfqQ/YcA+wJHBCcFIAa0B7kJ4AsNDnsNzQt5CdgGBAWWA1cCOgEiAAL/+P1m/E767Pdp9WP0RPSt9If1qfYZ+Jn56foq/H39tQE2BaYIDwxoD5ERJRGoD7wNgwsDCTUGdQPjAIL+QPz0+Vn3ovTF8ffuQO/A8PHydPUL+L76Tv16/14BHwP/BE4Hvwk/DMQOBw/eDQEM7gnYB7YFgwOFAcz/R/7X/P76ufgy9nnz8fFR8oTzPvUa9+n4zfqJ/B/+r/9GAU4D5wXcCNwLaQ5+DrcNaQzeCiUJKwchBR8DFAES//38W/pJ9wn0t/AD8Jjw8/HM8+31XPi3+uf8HP9ZAaADWQZQCVwMVQ9wEKsPGA4jDOkJYwe9BDkC6v/I/cX7nPk397r0EvJR8Pnwm/LC9CH3ffn0+yz+EgC4AVYDIwVEB4IJ0QsZDqwNWwyMCqYIyAbUBNECDQGT/zj+2vwC+8b4U/as8+3ydPO89F72C/jF+Xv7Af15/vX/ggGfAzYGCgneC4sNdA2cDFkL3QkvCEkGWQRvAnsAnv6B/OT58vbe8zDxA/HT8UTzGvUs93X5ofuy/c7/6QEiBL8GiQlcDBQPTg9LDrAMxAqsCF4GDATuAQUAP/6Y/J/6V/jY9TjzM/Lu8nP0XPZl+Hn6jfxV/tb/JwGDAiUEJwZcCKoKPAzMC5wKGAmBB/YFQgSeAjoBDwD8/sT9+Pu/+Uj3m/Rg9PX0J/aO9+v4XvrE+//8Nv5y/9cA3gJuBS0I/woQDO8LLQsZCtEITAerBQoEZwLBADb/PP2l+r73tvTG8rfye/PL9Gn2P/gw+gf80P2h/28BdwPuBZ8IWwugDYQNgwwXC2QJdQdPBTIDRgGK/+v9Xfxu+kL43vVq8zLzIvSz9Y33cvls+0393f4vAGwBswJXBEMGWQiEClYLuwqDCRUInwYmBYoDEwLdAND/0v6N/br7k/kw91H1SPX+9Sn3c/iy+Qz7Ufx5/Z/+zP9PAXUDCga2CHsLAAzAC/wK5QmTCAMHVwW1Aw0CcQDU/q38Cvot9zj0+/IQ89jzLvXV9r34nfpk/DD+/v/JAewDZgYLCasLNw33DAkMpwryCAIH5ATaAgIBUf+9/R38JPr195P1f/Oo86X0J/bt98H5r/ty/fP+PgCGAd8ClwSKBp8IwwoIC2MKPwnjB3sG8wRZA/YBzQC+/7T+P/1U+yX5yvaX9bb1hPa79xD5cPrZ+xH9Mf5L/3MA/AERBG0G3AjICgELjwqrCXwIHQeHBfQDdAL3AJb/EP79+4r57fZB9NHzPfRF9bj2bPhL+hL8s/1T/+sAjAKNBNMGNQmIC3QMFwwVC5QJvAelBYgDnAHq/1n+7PxN+2T5Tvcx9Qz0mfTX9YX3YflH+zv95P5DAHkBnQLTA08F/AbDCFUKBgoOCb4HQwbGBCkDugGbALf/6v4S/sH8D/sk+Qj3kvb59uP3B/kt+mv7m/ya/Yv+e/+FAAUC+wMnBnsI0AnuCX8JrQibB1gG8QSWA0cC/wC3/xz+9fuF+fb27PSn9Bv1GfZw9/r4rvpU/O79h/8cAc0C2AQZB2UJogvMCyoLBAp7CK4GrwS9AgUBfP8P/r78JvtT+Vv3ZvXx9Kn18vaW+FX6Kvzn/Vv/kACsAbIC5ANUBe0GmQiLCRgJGgjXBngFEwTFAqoBwQDu/yP/Lf6+/AL7EPku9wT3fvdU+Fj5bPql+8f8x/2+/rn/3gCBAn8EpgbzCLgJoAkICRwI+AahBTcE5QKXAVIAAP9J/TL77/ia9lX1XfUC9iP3i/gf+sr7ZP3o/lsAxAFZAz0FSQdTCdYKqgrcCZgICgdYBYUD0wFaAAj/1P2l/C77gvnB9wf2J/b89kD4wPlO+/H8av6b/5sAigFoAo8D+gSMBjIIqggrCEIHHwbrBKEDYQJeAYkAxf8G//79jfzf+v/4tfe09z74EfkH+g37Mfw2/Sb+Df8CADIB5ALfBAcHIwmXCW4J3ggACOEGhwUfBMgCeAEtAMf+8/zX+pr4UvaP9av1VvZj98L4WvoA/I79C/96AOUBkAN6BX4HeAlzCjcKdAlFCMkGHwVdA8EBVQAK/939m/wW+2T5qvdg9pz2aPeR+O35Zvv4/Fn+ff9/AHEBYwKhAxkFsAZZCHAI6wcWBxMG8gSpA3gCfgGmANn/CP/Y/VP8mPq0+Nj35vdi+Bn5//kR+y/8Mf0l/hf/HAByASwDGAUoB64I8wi0CBsINwcgBtAEggNBAgkB0P9l/pj8lvp7+IH2Uva89on3m/jk+Vn7z/wv/n7/wQAJApgDWgUsBwQJfQksCWIIQgfiBVQExwJqATQAGf8M/sX8P/uU+ev3H/ds9zH4Q/l/+tb7OP10/oP/fgBnAWkCtQMwBcEGCwgCCH4HrgauBY4ESQMtAj8BZgCX/7H+af3d+yn6YfgI+Ez45Piu+Z76ufvQ/M39wf63/7cADQKsA3IFWQdICFMI7wc8B0MGFgXSA6UChgFzAFn//P1N/HT6i/g39yH3k/de+G35pvoI/GP9qf7f/wsBSwLNA3YFKwfGCNoIZgiMB2oGGAW9A3ACSAE1ADb/Nv7z/Hj75flM+On3Pvj2+Ov5EPtZ/Jv9sf6m/40AYQFnAq0DGAWhBncHUQfGBvcF/wTlA78CwgHrACMAZP99/kb93vtT+v744vg++dj5nPqB+4r8gv1d/ij/8//SAAkCdwMNBcQGOAceB6sG/AUfBRQECQMXAjQBWABt/zP+uvwh+3T5ovie+AL5rfmV+qT7yfzd/d7+0v/DAOYBTQPTBG0GlAevB1gHngahBX8EPgMVAg0BGgA5/0b+Ff24+0z67vjT+Cj50/m3+sH76Pz+/en+vP9+ADYBLAJXA6AEAQZyBlAG1gUiBUYEQwNNAoMB1AAxAJH/tf6Y/VH87PoJ+vL5Mvqv+lf7IvwF/dH9hf4x/9z/rQDtAVEDzQQcBmgGTQbhBTsFbQR0A4cCrQHiABoARf8n/tz8d/sE+pf5n/kF+q36iPuJ/In9bP45//r/tgCtAdoCHARuBQ8GDwa2BRkFSQRYA18ChAHEABcAeP+2/rn9mvxl+4H6a/qo+in72/uo/Iv9Vf75/o7/GAC1AJQBoQLLA/wENgUgBcYEPwSVA8wCDwJzAeYAYADV/wT//f3S/I/7/fri+hP7evsP/Mr8if0u/sD+UP/g/6sAsgHcAh4E+gQyBRsFwAQ0BIUDuQL9AVMBtwAfAGn/cv5X/Sf8F/vS+vX6Xfvz+6L8cf0w/tX+Z//v/34ASwFAAkkDXgSxBLMEbATxA08DjwLUAToBtQBCANX/L/9Q/lb9SPy3+577x/sm/K78Uf34/YX+/f5s/9X/YQAsARoCIQPzAysEJwTrA4ID9wJSAr8BRwHaAHMA9/85/03+RP0w/N37zPv6+1T80/xy/Qv+i/7+/nD/6P+cAHoBcwJ+AwEEKQQQBMIDSQOoAgACcQH5AIwAJACM/7/+1/3d/DH8AfwT/GD81vxj/QX+lP4L/3T/0/9JAPkAxgGkAm8DqAOqA3MDDwOQAvYBbAH/AKUAWQAGAHn/vP7o/Qb9svyZ/Lj8Av1t/fD9a/7K/hv/ZP+s/yQA0ACZAXcCAAM1AzsDEQPAAk4C0gFuAR4B1gCRACgAhv+9/tr9HP3V/L/83Pwf/X/9+v1o/sD+Ef9g/8H/WgAVAegBxwIaAz8DLQPxApICEQKTAS8B3wCWAEoAyP8b/1j+h/0Z/e38+fwy/Yz9A/58/t/+Lf9w/6z/EACjAEsBAgKIAr4CxwKhAlUC8gF/ASAB2gCmAHsASgDd/0X/k/7n/aP9gv2N/bv9Af5c/qb+2v4G/zD/ZP/Q/2UAEwHTATMCcgKFAnMCPQLlAYsBSwEYAeoAuwBbAMv/G/9X/s79h/1s/X39s/0F/mP+r/7q/iL/WP+u/zEAzQB5ARACVQJ3AmwCOwLuAYQBKAHkALMAjABYAPL/a//S/i7+6/3I/dT9BP5L/qb+9v4t/1P/b/+K/9X/QwDDAFABogHVAeUB0QGfAVUBDAHdAMIAtgCyAIgAKgCv/x7/qv5o/kP+Q/5g/o/+yf7v/gP/Ef8d/z7/lf8MAJkAKAF3AbUBzwHJAaQBZQEwARIB/wDwANgAiwAVAIb/6P6J/kT+KP4t/lP+k/7R/vf+Ef8p/0L/hv/t/2YA7gBUAZcBuwG6AZcBWAEPAdoAuwCsAKQAggAzAMz/VP/n/qv+iP6K/qv+2/4Z/0X/Wf9f/13/Zf+c/+3/TAC3APIAJwE7ATEBEQHeALYAqgCwAMEA0wC3AG8ADwCh/1H/D//m/tv+6/4M/yj/LP8j/xf/Cv8e/2D/uv8mAIkA1wAWATcBOgEiAfwA6ADmAO0A9gDsALIAVwDo/3T/Jf/k/sX+w/7a/gX/I/8t/y7/Lv80/2X/sP8KAHEAuQD8ACABJQENAdsAuwCxALQAvgDJAK8AcQAhAMX/d/84/w//Bf8V/zn/X/9y/3D/Y/9P/1D/eP+y//r/QgB8AK4AwgC9AKYAgwBzAHsAlAC3AM8AvQCPAE8ABgDN/5D/bf9h/2r/fv+G/3X/V/8z/xD/E/85/3P/vP/+/0cAgQChAKcAmQCPAJ0AuADbAAABBgHjAKgAXAAPAMb/hP9b/03/U/9i/2D/TP8z/xj/DP8n/1n/nP/m/yoAcACcAKwApACLAH8AigCiAMAA2QDNAKcAcgA0APr/uv+R/4D/hv+e/6z/ov+H/2T/Pf8z/0b/Zv+S/8T///8xAEsATgBCADcAQwBkAJMAyQDrAOgAzwCnAHgAPgAAANn/x//D/8X/tf+R/2L/L/8D///+Hf9O/4j/yf8YAFMAdwCFAIIAhQCcALwA4QADAQYB6AC4AHwAOgDu/63/gv9y/3X/ev9s/1H/Mv8S/wr/I/9N/4X/w/8JAEoAdQCKAIsAfwCBAJQAsADQAOIA1ACxAIMASgANAND/qf+Z/5z/rP+0/6f/iv9l/0L/Qf9W/3f/o//V/xIAQABWAFkATABEAE0AaQCQALsAygC9AJ8AdgBGABAA4P/C/7j/uf++/7P/lv9v/0P/Jv8r/0T/bP+d/9n/GgBHAF0AYgBbAGAAdwCZAL8A3ADZALsAjwBZAB4A2v+p/47/iP+R/5j/jP92/1v/Qf9C/1v/gv+1/+v/KgBdAHgAewBrAFgAVQBjAHoAlQCdAIsAbABFABgA6v+//6n/p/+z/8b/zv/E/7D/lf+C/4X/lv+v/8//8/8cADQAOwA1ACYAIAAoAD8AXAB4AH4AcwBfAEQAJgD//+L/0//S/9j/3P/T/8D/qf+P/4X/jf+e/7f/1f/6/xsAMAA2ADQALgAxAD0ATgBhAGsAYwBRADkAHgAAAOL/zv/H/8n/0f/U/8//xv+8/7X/uf/G/9j/7f8DABwALAAyAC4AJAAcABsAIAAoADAALwAnABwADgAAAPH/5f/h/+T/6//y//T/8f/r/+P/4P/i/+f/7//4/wIACwAPAA8ACwAHAAUACAANABQAGAAYABUAEAAKAAQA/f/5//j/+f/7//v/+v/3//T/8v/y//T/9//6//3/AAADAAQAAwACAAIAAgACAAIAAQAAAAAA",
	["notify_error"] = "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",
	["loader_end"] = "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4f7n/uz+8P7z/vT+9/78/gP/Cv8Q/xb/Gv8d/yL/J/8t/zP/Of88/0D/Q/9J/1D/V/9f/2b/a/9u/3D/dP95/4D/iP+Q/5b/m/+f/6X/qv+t/7P/uf++/8P/yf/O/9T/2v/g/+f/7P/x//X/+f/9/wEABwANABQAGwAgACYAKwAvADMAOAA9AEEARwBMAFEAVwBeAGQAaABtAHAAdAB4AHwAgQCGAIsAkQCXAJsAnwCjAKcAqQCuALEAtgC7AL8AxADIAM0A0gDWANcA2gDcAN8A4gDnAOwA8QD1APkA+wD+AAABAwEGAQgBCgENAQ8BFAEXARoBHQEfASEBIgEkASUBJgEpASwBMAEyATQBNwE4ATkBOgE6ATwBPAE9AT8BQQFCAUUBRgFIAUcBRwFGAUUBRQFGAUgBSgFKAUsBTAFMAUoBSgFKAUkBSQFIAUgBSAFJAUkBSQFIAUgBRgFEAUEBPwE+AT4BPgE+AT4BPQE7ATkBNwE1ATMBMAEvASwBKwEqASkBKAEmASMBIAEdARoBFwEVARMBEgERAQ4BDAEJAQYBAgH/APwA+QD2APMA8ADtAOsA6gDnAOQA4ADcANcA0wDPAM0AywDJAMYAwwC+ALoAtwCzAK8AqwCnAKMAnwCcAJoAlwCVAJEAjACHAIIAfQB6AHcAcwBwAGwAaQBmAGEAXABYAFQATwBLAEcARABAAD0AOgA3ADQAMAArACUAIAAbABcAFAARAA8ADAAIAAQAAAD8//j/9P/w/+z/6f/m/+L/4P/d/9r/1v/S/83/yP/E/8D/vf+6/7n/tv+z/6//q/+o/6T/oP+c/5n/lv+U/5H/jv+M/4r/h/+E/4D/fP94/3X/c/9x/3H/b/9s/2j/ZP9h/1//Xv9c/1r/Vv9S/0//Tv9O/0//Tv9M/0j/Q/8//zz/PP89/z3/Pf86/zf/NP8x/zH/MP8w/y//Lf8q/yj/J/8n/yn/Kf8p/yb/I/8f/x3/Hv8f/yH/If8h/x//HP8b/xv/HP8c/x3/HP8a/xj/GP8Z/xz/Hv8f/x7/HP8Z/xj/Gf8b/x7/IP8h/yD/H/8e/x//If8j/yP/JP8k/yP/JP8m/yn/LP8v/y//Lf8s/yv/LP8u/zL/Nv85/zn/Of85/zn/PP8//0H/Q/9D/0P/RP9G/0r/Tf9Q/1P/U/9T/1P/VP9X/1v/X/9i/2P/ZP9k/2b/aP9s/3D/cv90/3T/df94/3z/gf+F/4n/i/+M/43/j/+T/5j/nf+h/6P/pP+m/6f/qv+v/7P/t/+5/7r/u/+9/8D/xP/H/8v/zf/P/8//0f/T/9b/2v/d/9//4P/h/+L/5f/o/+v/7v/w//H/8f/y//T/9v/5//z//v//////AAAAAAIABAAGAAgACQAJAAkACgAMAA8AEAARABIAEgASABIAFAAVABcAGAAZABkAGAAYABkAGwAcAB0AHQAdABwAHAAdAB4AHwAfAB8AHwAeAB4AHwAfACAAIAAgAB8AHwAeAB4AHwAfAB8AHgAeAB0AHQAcAB0AHQAcABwAGwAaABkAGQAZABkAGAAYABcAFgAVABUAFAAUABMAEgARABEAEAAPAA8ADgANAA0ADAALAAoACQAIAAgABwAGAAUABAAEAAMAAgABAAAAAAA=",
	["loader_swell"] = "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",
}

-- vol = base loudness, jit = random pitch variation, gap = min seconds between plays
local SFX_PROFILE = {
	hover = { vol = 0.35, jit = 0.05, gap = 0.07 },
	click = { vol = 0.8, jit = 0.04, gap = 0.03 },
	toggle_on = { vol = 0.75, jit = 0.0, gap = 0.04 },
	toggle_off = { vol = 0.7, jit = 0.0, gap = 0.04 },
	tab = { vol = 0.7, jit = 0.02, gap = 0.05 },
	slider = { vol = 0.5, jit = 0.0, gap = 0.035 },
	select = { vol = 0.75, jit = 0.02, gap = 0.04 },
	dd_open = { vol = 0.7, jit = 0.0, gap = 0.05 },
	dd_close = { vol = 0.65, jit = 0.0, gap = 0.05 },
	open = { vol = 0.85, jit = 0.0, gap = 0.2 },
	close = { vol = 0.85, jit = 0.0, gap = 0.2 },
	notify_info = { vol = 0.75, jit = 0.0, gap = 0.08, clone = true },
	notify_success = { vol = 0.75, jit = 0.0, gap = 0.08, clone = true },
	notify_warn = { vol = 0.75, jit = 0.0, gap = 0.08, clone = true },
	notify_error = { vol = 0.8, jit = 0.0, gap = 0.08, clone = true },
	loader_swell = { vol = 0.8, jit = 0.0, gap = 1 },
	loader_end = { vol = 0.95, jit = 0.0, gap = 1 },
}

-- used only when custom assets are unavailable (best effort, built-in client sounds)
local SFX_FALLBACK = {
	click = "rbxasset://sounds/clickfast.wav", select = "rbxasset://sounds/clickfast.wav",
	tab = "rbxasset://sounds/clickfast.wav", toggle_on = "rbxasset://sounds/switch.wav",
	toggle_off = "rbxasset://sounds/switch.wav", notify_info = "rbxasset://sounds/electronicpingshort.wav",
	notify_success = "rbxasset://sounds/electronicpingshort.wav", notify_warn = "rbxasset://sounds/electronicpingshort.wav",
	notify_error = "rbxasset://sounds/electronicpingshort.wav",
}

local Sfx = { Enabled = true, Volume = 0.6, Bank = {}, Last = {}, Ready = false, _started = false }
Singularity.Sfx = Sfx

local B64 = {}
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do B64[string.byte(chars, i)] = i - 1 end
end

local function nativeB64()
	local candidates = {
		function() return crypt.base64decode end,
		function() return crypt.base64.decode end,
		function() return base64_decode end,
		function() return base64decode end,
		function() return syn.crypt.base64.decode end,
	}
	for _, get in ipairs(candidates) do
		local ok, fn = pcall(get)
		if ok and type(fn) == "function" then return fn end
	end
end

local function b64decode(s)
	local native = nativeB64()
	if native then
		local ok, r = pcall(native, s)
		if ok and type(r) == "string" and #r > 0 then return r end
	end
	local out, n = {}, 0
	local pads = (string.sub(s, -2) == "==") and 2 or ((string.sub(s, -1) == "=") and 1 or 0)
	for i = 1, #s, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = (B64[a] or 0) * 262144 + (B64[b] or 0) * 4096 + (B64[c or 65] or 0) * 64 + (B64[d or 65] or 0)
		n = n + 1
		out[n] = string.char(math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
		if n % 12000 == 0 then task.wait() end
	end
	local r = table.concat(out)
	if pads > 0 then r = string.sub(r, 1, #r - pads) end
	return r
end

local function customAsset(path)
	local fn = (type(getcustomasset) == "function" and getcustomasset) or (type(getsynasset) == "function" and getsynasset) or nil
	if not fn then return nil end
	local ok, id = pcall(fn, path)
	if ok and type(id) == "string" and id ~= "" then return id end
	return nil
end

function Sfx:Init()
	if self._started then return end
	self._started = true
	local canFiles = type(writefile) == "function" and type(isfile) == "function"
		and type(isfolder) == "function" and type(makefolder) == "function"
	local assets = {}
	if canFiles then
		pcall(function()
			if not isfolder(Singularity.Folder) then makefolder(Singularity.Folder) end
			if not isfolder(Singularity.Folder .. "/sfx") then makefolder(Singularity.Folder .. "/sfx") end
		end)
		for name, data in pairs(SFX_DATA) do
			local path = Singularity.Folder .. "/sfx/" .. name .. "_v" .. SFX_VERSION .. ".wav"
			pcall(function()
				if not isfile(path) then writefile(path, b64decode(data)) end
			end)
			assets[name] = customAsset(path)
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "SingularitySFX"
	local okParent = pcall(function() folder.Parent = SoundService end)
	if not okParent then folder.Parent = workspace.CurrentCamera or workspace end
	Cleanups[#Cleanups + 1] = function() folder:Destroy() end
	self.Folder = folder

	local all = {}
	for name, prof in pairs(SFX_PROFILE) do
		local id = assets[name] or SFX_FALLBACK[name]
		if id then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = id
			s.Volume = prof.vol * self.Volume
			s.Parent = folder
			self.Bank[name] = s
			all[#all + 1] = s
		end
	end
	self.Ready = true
	task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync(all) end) end)
end

function Sfx:Await(timeout)
	local t0 = os.clock()
	while not self.Ready and os.clock() - t0 < (timeout or 2) do task.wait() end
end

function Sfx:Play(name, speed)
	if not self.Enabled or self.Volume <= 0 then return end
	local s = self.Bank[name]
	local prof = SFX_PROFILE[name]
	if not s or not prof then return end
	local now = os.clock()
	if now - (self.Last[name] or 0) < prof.gap then return end
	self.Last[name] = now
	local rate = (speed or 1) * (1 + (math.random() * 2 - 1) * prof.jit)
	if prof.clone then
		local c = s:Clone()
		c.Volume = prof.vol * self.Volume
		c.PlaybackSpeed = rate
		c.Parent = self.Folder
		c:Play()
		task.delay(4, function() c:Destroy() end)
		return
	end
	s.Volume = prof.vol * self.Volume
	s.PlaybackSpeed = rate
	s.TimePosition = 0
	s:Play()
end

function Singularity:PlaySound(name, speed) Sfx:Play(name, speed) end
task.spawn(function() Sfx:Init() end)

------------------------------------------------------------------------
-- icons: Lucide (latte-soft/lucide-roblox) loaded in the background.
-- Tabs show a small ring-and-letter glyph until the library answers,
-- and keep it if the library cannot be reached.
------------------------------------------------------------------------
local LUCIDE_URL = "https://github.com/latte-soft/lucide-roblox/releases/latest/download/lucide-roblox.luau"

-- tab name (lowercase) -> Lucide icon name; override per tab with CreateTab(name, { Icon = "..." })
local TAB_ICONS = {
	combat = "crosshair", aim = "crosshair", target = "target", movement = "footprints", move = "footprints",
	visuals = "eye", visual = "eye", esp = "eye", render = "eye", world = "globe", player = "user",
	misc = "sparkles", utility = "wrench", tools = "wrench", settings = "settings", config = "settings",
	main = "layout-grid", home = "layout-grid", info = "info",
}
local DEFAULT_TAB_ICON = "orbit"

local Icons = { _lib = env.__SingularityLucide, _tried = false, _binds = {} }
Singularity.Icons = Icons

local function httpGet(url)
	local ok, res = pcall(function() return game:HttpGet(url) end)
	if ok and type(res) == "string" and #res > 0 then return res end
	local req = (type(request) == "function" and request) or (type(http_request) == "function" and http_request)
		or (syn and type(syn.request) == "function" and syn.request) or nil
	if req then
		local ok2, r = pcall(req, { Url = url, Method = "GET" })
		if ok2 and type(r) == "table" and type(r.Body) == "string" and #r.Body > 0 then return r.Body end
	end
	return nil
end

function Icons:Resolve(name, px)
	local lib = self._lib
	if not lib then return nil end
	local ok, a = pcall(lib.GetAsset, name, px or 48)
	if ok and type(a) == "table" and type(a.Url) == "string" then return a end
	return nil
end

function Icons:Apply(label, name)
	local a = self:Resolve(name, 48)
	if not a then return false end
	label.Image = a.Url
	label.ImageRectSize = a.ImageRectSize
	label.ImageRectOffset = a.ImageRectOffset
	return true
end

function Icons:Bind(label, name, onResult)
	if self:Apply(label, name) then
		onResult(true)
	else
		self._binds[#self._binds + 1] = { label, name, onResult }
	end
end

function Icons:Load()
	if self._tried then return end
	self._tried = true
	task.spawn(function()
		if not self._lib then
			local src = httpGet(LUCIDE_URL)
			local fn = src and type(loadstring) == "function" and loadstring(src) or nil
			if fn then
				local ok, lib = pcall(fn)
				if ok and type(lib) == "table" and type(lib.GetAsset) == "function" then
					self._lib = lib
					env.__SingularityLucide = lib
				end
			end
		end
		for _, b in ipairs(self._binds) do
			if b[1].Parent then b[3](self:Apply(b[1], b[2])) end
		end
		table.clear(self._binds)
	end)
end
Icons:Load()

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local function new(class, props, kids)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then
		o.BorderSizePixel = 0
		if o:IsA("GuiButton") then
			o.AutoButtonColor = false
			o.MouseEnter:Connect(function() Sfx:Play("hover") end)
		end
	end
	if TEXT_CLASSES[class] then
		o.BackgroundTransparency = 1
		o.FontFace = Fonts.Body
		o.TextColor3 = Theme.Text
		o.TextSize = 13
		o.Text = ""
	end
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	if kids then
		for _, c in ipairs(kids) do c.Parent = o end
	end
	o.Parent = parent
	return o
end

local function corner(parent, r, scale)
	return new("UICorner", { CornerRadius = UDim.new(scale or 0, r or 0), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end

local function pad(parent, l, t, r, b)
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0), PaddingTop = UDim.new(0, t or 0),
		PaddingRight = UDim.new(0, r or 0), PaddingBottom = UDim.new(0, b or 0), Parent = parent,
	})
end

local function list(parent, padding, props)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, padding or 0)
	for k, v in pairs(props or {}) do l[k] = v end
	l.Parent = parent
	return l
end

local function guiParent()
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and typeof(hui) == "Instance" then return hui end
	local ok2 = pcall(function()
		local probe = Instance.new("Folder")
		probe.Parent = CoreGui
		probe:Destroy()
	end)
	if ok2 then return CoreGui end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function makeGui(name, order, ignoreInset)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = ignoreInset or false
	gui.DisplayOrder = order or 100
	if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
	gui.Parent = guiParent()
	Guis[#Guis + 1] = gui
	return gui
end

local function guiSize(gui)
	if gui and gui.AbsoluteSize.X > 0 then return gui.AbsoluteSize end
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return Vector2.new(v.X, v.Y - 36)
end

------------------------------------------------------------------------
-- input helpers
------------------------------------------------------------------------
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function trackDrag(hit, handlers)
	return connect(hit.InputBegan, function(input)
		if not isPress(input) then return end
		local startPos = input.Position
		local moved = false
		if handlers.Begin then handlers.Begin(input) end
		local moveConn, endConn
		local function finish()
			if moveConn then moveConn:Disconnect() end
			if endConn then endConn:Disconnect() end
			if handlers.End then handlers.End(moved) end
		end
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
				local d = i.Position - startPos
				if d.Magnitude > 4 then moved = true end
				if handlers.Move then handlers.Move(i, d) end
			end
		end)
		endConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then finish() end
		end)
	end)
end

local function clampPos(target, g, minX, minY, maxX, maxY)
	if maxX < minX then maxX = minX end
	if maxY < minY then maxY = minY end
	local p = target.Position
	local cx = p.X.Scale * g.X + p.X.Offset
	local cy = p.Y.Scale * g.Y + p.Y.Offset
	cx = math.clamp(cx, minX, maxX)
	cy = math.clamp(cy, minY, maxY)
	return UDim2.new(p.X.Scale, cx - p.X.Scale * g.X, p.Y.Scale, cy - p.Y.Scale * g.Y)
end

-- limits() -> gui size, minX, minY, maxX, maxY  (limits on the target's centre, in px)
local function makeDraggable(handle, target, limits, onClick)
	local startPos
	trackDrag(handle, {
		Begin = function() startPos = target.Position end,
		Move = function(_, d)
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			if limits then target.Position = clampPos(target, limits()) end
		end,
		End = function(moved)
			if not moved and onClick then onClick() end
		end,
	})
end

------------------------------------------------------------------------
-- FX: spring engine, ripples, glass, shadows, cursor reactions
-- One Heartbeat driver steps every live spring and ticker; springs that
-- have settled leave the list, so an idle interface costs nothing.
------------------------------------------------------------------------
local FX = {}
do
	local springs = {}
	local tickers = {}
	local mouse = Vector2.new(-1000, -1000)

	local function wake(s)
		if not s.on then
			s.on = true
			springs[#springs + 1] = s
		end
	end

	-- freq: natural frequency (rad/s), damp: damping ratio (<1 overshoots)
	function FX.Spring(initial, freq, damp, apply)
		local s = { x = initial, v = 0, g = initial, f = freq or 16, z = damp or 0.78, apply = apply, on = false }
		function s:Goal(g)
			self.g = g
			wake(self)
		end
		function s:Snap(x)
			self.x, self.v, self.g = x, 0, x
			if self.apply then self.apply(x) end
		end
		function s:Kick(v)
			self.v = self.v + v
			wake(self)
		end
		return s
	end

	local exp, cos, sin, sqrt, abs = math.exp, math.cos, math.sin, math.sqrt, math.abs
	local function step(s, dt)
		local w, z = s.f, s.z
		local o, v = s.x - s.g, s.v
		local decay = exp(-z * w * dt)
		if z < 0.999 then
			local wd = w * sqrt(1 - z * z)
			local c, sn = cos(wd * dt), sin(wd * dt)
			local b = (v + z * w * o) / wd
			s.x = s.g + decay * (o * c + b * sn)
			s.v = decay * (v * c - (z * w * b + wd * o) * sn)
		else
			local c1 = v + w * o
			s.x = s.g + decay * (o + c1 * dt)
			s.v = decay * (v - w * c1 * dt)
		end
	end

	-- tickers run every frame while they return true
	function FX.Ticker(fn)
		local t = { fn = fn }
		tickers[#tickers + 1] = t
		return t
	end

	local clock = 0
	function FX.Time() return clock end
	function FX.Mouse() return mouse end

	connect(RunService.Heartbeat, function(dt)
		if dt > 0.05 then dt = 0.05 end
		clock = clock + dt
		local ok, m = pcall(function() return UserInputService:GetMouseLocation() end)
		if ok and m then mouse = m end
		local n, i = #springs, 1
		while i <= n do
			local s = springs[i]
			step(s, dt)
			local eps = s.eps or 0.0006
			local rest = abs(s.x - s.g) < eps and abs(s.v) < eps * 10
			if rest then s.x, s.v = s.g, 0 end
			if s.apply then s.apply(s.x) end
			if rest then
				s.on = false
				springs[i] = springs[n]
				springs[n] = nil
				n = n - 1
			else
				i = i + 1
			end
		end
		for k = #tickers, 1, -1 do
			local t = tickers[k]
			if t.dead or t.fn(dt, clock) == false then table.remove(tickers, k) end
		end
	end)
	Cleanups[#Cleanups + 1] = function()
		table.clear(springs)
		table.clear(tickers)
	end

	-- Spring-driven UIScale / offsets ----------------------------------
	-- FX.ScaleSpring(uiScale, freq, damp) -> spring (Goal(scale))
	function FX.ScaleSpring(us, freq, damp)
		return FX.Spring(us.Scale, freq or 18, damp or 0.62, function(x) us.Scale = x end)
	end

	-- 2D offset spring for a GuiObject's Position (offset component only).
	function FX.OffsetSpring(inst, base, freq, damp)
		local sx = FX.Spring(0, freq or 14, damp or 0.7)
		local sy = FX.Spring(0, freq or 14, damp or 0.7)
		local function apply()
			inst.Position = UDim2.new(base.X.Scale, base.X.Offset + sx.x, base.Y.Scale, base.Y.Offset + sy.x)
		end
		sx.apply, sy.apply = apply, apply
		return {
			Goal = function(_, x, y) sx:Goal(x) sy:Goal(y) end,
			Snap = function(_, x, y) sx:Snap(x) sy:Snap(y) apply() end,
		}
	end

	-- Ripple: a soft expanding disc from the press point, clipped to the button's
	-- rounded shape by a short-lived CanvasGroup.
	function FX.Ripple(host, cornerPx, color, px, py)
		local abs, size = host.AbsolutePosition, host.AbsoluteSize
		if size.X < 2 then return end
		local lx, ly = size.X / 2, size.Y / 2
		if px and py then lx, ly = math.clamp(px - abs.X, 0, size.X), math.clamp(py - abs.Y, 0, size.Y) end
		local clip = new("CanvasGroup", {
			Name = "Ripple", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = host,
		})
		corner(clip, cornerPx or 8)
		local reach = math.sqrt(size.X * size.X + size.Y * size.Y) * 2
		local disc = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(lx, ly), Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = color or Theme.Hot, BackgroundTransparency = 0.72, Parent = clip,
		})
		corner(disc, 0, 1)
		tween(disc, ti(0.62, Enum.EasingStyle.Cubic), { Size = UDim2.fromOffset(reach, reach) })
		tween(disc, ti(0.62, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
		task.delay(0.7, function() clip:Destroy() end)
	end

	-- Animated border: a UIStroke whose gradient slowly rotates. Returns the stroke.
	-- `strength` is the stroke transparency at rest; the highlight arc travels around.
	function FX.RimStroke(parent, thickness, period, baseTransparency)
		local st = new("UIStroke", {
			Thickness = thickness or 1.2, Color = Color3.new(1, 1, 1), Transparency = baseTransparency or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
		})
		local g = new("UIGradient", { Rotation = 0, Parent = st })
		onAccent(function(a, h)
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Frost),
				ColorSequenceKeypoint.new(0.28, Theme.Line),
				ColorSequenceKeypoint.new(0.5, h),
				ColorSequenceKeypoint.new(0.62, a),
				ColorSequenceKeypoint.new(0.8, Theme.Line),
				ColorSequenceKeypoint.new(1, Theme.Frost),
			})
		end)
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.72),
			NumberSequenceKeypoint.new(0.5, 0.05), NumberSequenceKeypoint.new(0.7, 0.72), NumberSequenceKeypoint.new(1, 0),
		})
		local rate = 360 / (period or 14)
		FX.Ticker(function(dt)
			if not g.Parent then return false end
			g.Rotation = (g.Rotation + rate * dt) % 360
		end)
		return st, g
	end

	-- Glass surface: tinted translucent body with a diagonal specular sheen.
	function FX.Glass(parent, radius, props)
		props = props or {}
		local f = new("Frame", {
			Name = props.Name or "Glass", BackgroundColor3 = props.Color or Theme.Glass,
			BackgroundTransparency = props.Transparency or 0.22, Size = props.Size or UDim2.fromScale(1, 1),
			Position = props.Position or UDim2.new(), AnchorPoint = props.AnchorPoint or Vector2.new(),
			ZIndex = props.ZIndex or 1, Parent = parent,
		})
		if radius == "circle" then corner(f, 0, 1) else corner(f, radius or 14) end
		new("UIGradient", {
			Rotation = 62,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.55, 0.12), NumberSequenceKeypoint.new(1, 0.3),
			}),
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 40, 62)), ColorSequenceKeypoint.new(1, Theme.Glass),
			}),
			Parent = f,
		})
		return f
	end
end

------------------------------------------------------------------------
-- geo: full-screen geometry background. Thin white construction lines,
-- nodes and wireframe solids drift across the whole screen, bouncing off
-- the edges so the field always covers the viewport.
--   Geo.Field(parent, { ZIndex, Density, Solids, Parallax })
--       :Fade(target, seconds | TweenInfo)   :SetQuality(q)   :Destroy()
--   Geo.Solid(parent, "ico" | "octa", { Radius, Color, Thickness, Opacity,
--             Dot, SpinX, SpinY, SpinZ })
--       .alpha  .scale  :Step(dt)  :Destroy()
--   Vignette(parent, color, { ZIndex, Strength })
--       :Fade(level, seconds | TweenInfo)   :Destroy()
------------------------------------------------------------------------
local Geo = {}

local QUALITY = { Ultra = 1, High = 0.8, Balanced = 0.6, Low = 0.35 }
local PHI = (1 + math.sqrt(5)) / 2

local function fadeInfo(t)
	if typeof(t) == "TweenInfo" then return t end
	return ti(tonumber(t) or 0.5, Enum.EasingStyle.Quad)
end

-- unit-radius polyhedra: vertices plus the edges between nearest neighbours
local SHAPES = {}
do
	local function build(verts)
		local r = math.sqrt(verts[1][1] ^ 2 + verts[1][2] ^ 2 + verts[1][3] ^ 2)
		local vs = {}
		for i, v in ipairs(verts) do
			vs[i] = { v[1] / r, v[2] / r, v[3] / r }
		end
		local function d2(a, b)
			return (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2
		end
		local minD = math.huge
		for i = 1, #vs do
			for j = i + 1, #vs do
				local d = d2(vs[i], vs[j])
				if d < minD then minD = d end
			end
		end
		local edges = {}
		for i = 1, #vs do
			for j = i + 1, #vs do
				if d2(vs[i], vs[j]) < minD * 1.01 then
					edges[#edges + 1] = { i, j }
				end
			end
		end
		return { verts = vs, edges = edges }
	end

	SHAPES.octa = build({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } })

	local ico = {}
	for _, a in ipairs({ -1, 1 }) do
		for _, b in ipairs({ -PHI, PHI }) do
			ico[#ico + 1] = { 0, a, b }
			ico[#ico + 1] = { a, b, 0 }
			ico[#ico + 1] = { b, 0, a }
		end
	end
	SHAPES.ico = build(ico)

	local cube = {}
	for _, a in ipairs({ -1, 1 }) do
		for _, b in ipairs({ -1, 1 }) do
			for _, c in ipairs({ -1, 1 }) do
				cube[#cube + 1] = { a, b, c }
			end
		end
	end
	SHAPES.cube = build(cube)
	SHAPES.tetra = build({ { 1, 1, 1 }, { 1, -1, -1 }, { -1, 1, -1 }, { -1, -1, 1 } })
end

local function rotate(p, ax, ay, az)
	local x, y, z = p[1], p[2], p[3]
	local c, s = math.cos(ax), math.sin(ax)
	y, z = y * c - z * s, y * s + z * c
	c, s = math.cos(ay), math.sin(ay)
	x, z = x * c + z * s, -x * s + z * c
	c, s = math.cos(az), math.sin(az)
	x, y = x * c - y * s, x * s + y * c
	return x, y, z
end

function Geo.Solid(parent, shape, opts)
	opts = opts or {}
	local model = SHAPES[shape] or SHAPES.ico
	local R = opts.Radius or 60
	local thick = opts.Thickness or 1
	local opacity = opts.Opacity or 1
	local dotPx = opts.Dot or 0
	local color = opts.Color or Theme.Frost

	-- centred holder: every child position is an offset from the parent's centre
	local root = new("Frame", {
		Name = "Solid", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), Parent = parent,
	})

	local edges, dots = {}, {}
	for i = 1, #model.edges do
		edges[i] = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, thick), Parent = root,
		})
	end
	if dotPx > 0 then
		for i = 1, #model.verts do
			local d = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BackgroundTransparency = 1,
				Size = UDim2.fromOffset(dotPx, dotPx), Parent = root,
			})
			corner(d, 0, 1)
			dots[i] = d
		end
	end

	local obj = {
		root = root, alpha = 1, scale = 1,
		ax = math.random() * 6.28, ay = math.random() * 6.28, az = math.random() * 6.28,
		sx = opts.SpinX or 0.3, sy = opts.SpinY or 0.4, sz = opts.SpinZ or 0.1,
	}

	function obj:Step(dt)
		self.ax = self.ax + self.sx * dt
		self.ay = self.ay + self.sy * dt
		self.az = self.az + self.sz * dt
		local a = self.alpha * opacity
		local s = R * self.scale
		local pts = {}
		for i, v in ipairs(model.verts) do
			local x, y, z = rotate(v, self.ax, self.ay, self.az)
			pts[i] = { x * s, y * s, (z + 1) * 0.5 } -- depth 0 (far) .. 1 (near)
		end
		for i, e in ipairs(model.edges) do
			local p, q = pts[e[1]], pts[e[2]]
			local dx, dy = q[1] - p[1], q[2] - p[2]
			local f = edges[i]
			f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), thick)
			f.Position = UDim2.new(0.5, (p[1] + q[1]) * 0.5, 0.5, (p[2] + q[2]) * 0.5)
			f.Rotation = math.deg(math.atan2(dy, dx))
			f.BackgroundTransparency = 1 - math.clamp(a * (0.35 + 0.65 * (p[3] + q[3]) * 0.5), 0, 1)
		end
		for i, d in ipairs(dots) do
			local p = pts[i]
			d.Position = UDim2.new(0.5, p[1], 0.5, p[2])
			d.BackgroundTransparency = 1 - math.clamp(a * (0.45 + 0.55 * p[3]), 0, 1)
		end
	end

	function obj:Destroy()
		root:Destroy()
	end

	return obj
end

function Geo.Field(parent, opts)
	opts = opts or {}
	local z = opts.ZIndex or 1
	local density = opts.Density or 1
	local parallax = opts.Parallax ~= false
	local frost = Theme.Frost

	local root = new("Frame", {
		Name = "GeoField", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true, ZIndex = z, Parent = parent,
	})
	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	alpha.Parent = root

	local vp = guiSize(root)
	local maxNodes = math.max(18, math.floor(math.clamp(vp.X * vp.Y / 20000, 24, 80) * density))
	local maxLinks = maxNodes * 3

	local nodes = {}
	for i = 1, maxNodes do
		local dot = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = frost, BackgroundTransparency = 1,
			Size = UDim2.fromOffset(3, 3), ZIndex = z + 1, Parent = root,
		})
		corner(dot, 0, 1)
		nodes[i] = {
			dot = dot,
			u = math.random(), v = math.random(),
			du = (math.random() - 0.5) * 0.035, dv = (math.random() - 0.5) * 0.035,
			ph = math.random() * 6.28,
			z = 0.45 + math.random() * 0.55,
			x = 0, y = 0,
		}
	end

	local links = {}
	for i = 1, maxLinks do
		links[i] = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = frost, BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1, 1), ZIndex = z, Parent = root,
		})
	end

	local solids, solidShapes = {}, { "ico", "octa", "cube", "tetra" }
	for i = 1, (opts.Solids or 2) do
		local holder = new("Frame", {
			BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0),
			Position = UDim2.fromOffset(0, 0), ZIndex = z, Parent = root,
		})
		solids[i] = Geo.Solid(holder, solidShapes[(i - 1) % #solidShapes + 1], {
			Radius = 60 + math.random() * 90, Color = frost, Thickness = 1, Opacity = 0.2,
			SpinX = (math.random() - 0.5) * 0.4, SpinY = (math.random() - 0.5) * 0.5, SpinZ = (math.random() - 0.5) * 0.25,
		})
		-- each shape drifts across the whole field and bounces off the edges, like the nodes
		solids[i].holder = holder
		solids[i].u, solids[i].v = math.random(), math.random()
		solids[i].du, solids[i].dv = (math.random() - 0.5) * 0.03, (math.random() - 0.5) * 0.03
	end

	local state = { dead = false, active = maxNodes }
	local function setQuality(q)
		local f = QUALITY[q] or QUALITY.Balanced
		state.active = math.max(6, math.floor(maxNodes * f + 0.5))
		state.solidCount = math.max(2, math.floor(#solids * f + 0.5))
	end
	setQuality(Singularity.Quality or "Balanced")

	FX.Ticker(function(dt, t)
		if state.dead or not root.Parent then return false end
		local a = alpha.Value
		if a < 0.004 then return true end
		local W, H = root.AbsoluteSize.X, root.AbsoluteSize.Y
		if W <= 0 or H <= 0 then return true end

		local n = state.active
		local linkDist = math.max(110, math.min(W, H) * 0.24)
		local linkDist2 = linkDist * linkDist

		for i, nd in ipairs(nodes) do
			if i <= n then
				local speed = parallax and nd.z or 1
				nd.u = nd.u + nd.du * speed * dt
				nd.v = nd.v + nd.dv * speed * dt
				if nd.u < 0 then nd.u, nd.du = 0, math.abs(nd.du) elseif nd.u > 1 then nd.u, nd.du = 1, -math.abs(nd.du) end
				if nd.v < 0 then nd.v, nd.dv = 0, math.abs(nd.dv) elseif nd.v > 1 then nd.v, nd.dv = 1, -math.abs(nd.dv) end
				nd.x = nd.u * W + math.sin(t * 0.5 + nd.ph) * 6 * nd.z
				nd.y = nd.v * H + math.cos(t * 0.42 + nd.ph) * 6 * nd.z
				nd.dot.Position = UDim2.fromOffset(nd.x, nd.y)
				nd.dot.BackgroundTransparency = 1 - a * (0.35 + 0.5 * nd.z)
			else
				nd.dot.BackgroundTransparency = 1
			end
		end

		local used = 0
		for i = 1, n do
			local p = nodes[i]
			for j = i + 1, n do
				if used >= maxLinks then break end
				local q = nodes[j]
				local dx, dy = q.x - p.x, q.y - p.y
				local d2 = dx * dx + dy * dy
				if d2 < linkDist2 then
					used = used + 1
					local len = math.sqrt(d2)
					local f = links[used]
					f.Position = UDim2.fromOffset((p.x + q.x) * 0.5, (p.y + q.y) * 0.5)
					f.Size = UDim2.fromOffset(len, 1)
					f.Rotation = math.deg(math.atan2(dy, dx))
					f.BackgroundTransparency = 1 - a * (1 - len / linkDist) * 0.42
				end
			end
			if used >= maxLinks then break end
		end
		for k = used + 1, maxLinks do
			links[k].BackgroundTransparency = 1
		end

		for i, s in ipairs(solids) do
			local on = i <= state.solidCount
			s.holder.Visible = on
			if on then
				s.u = s.u + s.du * dt
				s.v = s.v + s.dv * dt
				if s.u < 0 then s.u, s.du = 0, math.abs(s.du) elseif s.u > 1 then s.u, s.du = 1, -math.abs(s.du) end
				if s.v < 0 then s.v, s.dv = 0, math.abs(s.dv) elseif s.v > 1 then s.v, s.dv = 1, -math.abs(s.dv) end
				s.holder.Position = UDim2.fromOffset(s.u * W, s.v * H)
				s.alpha = a * 0.8
				s:Step(dt)
			end
		end
		return true
	end)

	local field = { root = root, Solids = solids }

	function field:Fade(target, timeOrInfo)
		tween(alpha, fadeInfo(timeOrInfo), { Value = target })
	end

	function field:SetQuality(q)
		setQuality(q)
	end

	function field:Destroy()
		if state.dead then return end
		state.dead = true
		root:Destroy()
	end

	Cleanups[#Cleanups + 1] = function() field:Destroy() end
	return field
end

-- soft colour falloff around the screen edges (no image assets needed)
-- how far the falloff reaches in from each edge (1 = the original, 0.84 = slightly tighter)
local VIGNETTE_RADIUS = 0.84
local function Vignette(parent, color, opts)
	opts = opts or {}
	local z = opts.ZIndex or 1
	local strength = math.clamp(opts.Strength or 0.8, 0, 1)
	local radius = math.clamp(opts.Radius or VIGNETTE_RADIUS, 0.2, 1)

	local holder = new("Frame", {
		Name = "Vignette", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = parent,
	})
	local level = Instance.new("NumberValue")
	level.Value = 0
	level.Parent = holder

	local bands = {}
	local function band(pos, size, rot)
		local f = new("Frame", {
			BackgroundColor3 = color, BackgroundTransparency = 1, Position = pos, Size = size, ZIndex = z, Parent = holder,
		})
		new("UIGradient", {
			Rotation = rot,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1 - strength),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = f,
		})
		bands[#bands + 1] = f
	end
	local bw, bh = 0.34 * radius, 0.3 * radius
	band(UDim2.fromScale(0, 0), UDim2.fromScale(bw, 1), 0)
	band(UDim2.fromScale(1 - bw, 0), UDim2.fromScale(bw, 1), 180)
	band(UDim2.fromScale(0, 0), UDim2.fromScale(1, bh), 90)
	band(UDim2.fromScale(0, 1 - bh), UDim2.fromScale(1, bh), 270)

	connect(level.Changed, function(v)
		for _, f in ipairs(bands) do f.BackgroundTransparency = 1 - v end
	end)

	local vig = { root = holder }

	function vig:Fade(target, timeOrInfo)
		tween(level, fadeInfo(timeOrInfo), { Value = target })
	end

	function vig:Destroy()
		holder:Destroy()
	end

	Cleanups[#Cleanups + 1] = function() vig:Destroy() end
	return vig
end

------------------------------------------------------------------------
-- loading screen
------------------------------------------------------------------------
function Geo.Sigil(parent, size, color)
	local holder = new("Frame", {
		Name = "Sigil", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = parent,
	})
	local parts = {}
	local count = 6
	local radius = size * 0.3
	local c = size / 2
	for i = 1, count do
		local a = (i - 1) / count * math.pi * 2
		local dot = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(c + math.cos(a) * radius, c + math.sin(a) * radius),
			Size = UDim2.fromOffset(3, 3),
			BackgroundColor3 = color or Theme.Hot,
			BorderSizePixel = 0, ZIndex = 2, Parent = holder,
		})
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
		parts[i] = dot
	end
	return holder, parts
end

local CYAN = Color3.fromRGB(40, 210, 255)
local CYAN_HOT = Color3.fromRGB(176, 242, 255)
local CYAN_DEEP = Color3.fromRGB(8, 96, 128)

-- permanent credit under the loading-screen name. Not read from any config and not
-- exposed as an option; the label puts the text back if anything edits it.
local CREDIT_TEXT = "Made using Arios | Salfury scripts"

local DEFAULT_STEPS = {
	"Calibrating event horizon",
	"Mapping accretion disk",
	"Binding modules",
	"Stabilizing interface",
	"Crossing the threshold",
}

local function spaced(str)
	return (string.gsub(string.upper(str), ".", "%0 "):gsub("%s+$", ""))
end

function Singularity:CreateLoader(cfg)
	cfg = cfg or {}
	local gui = makeGui("SingularityLoader", 10000, true)
	local vp = guiSize(gui)
	local compact = vp.X < 700
	local emblemPx = math.clamp(math.floor(math.min(vp.X, vp.Y) * 0.34), 120, 240)
	local contentW = math.min(vp.X - 40, 380)
	local barW = math.floor(contentW * 0.8)

	-- the game stays visible underneath, just darkened
	local root = new("Frame", {
		Name = "Root", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), Active = true, Parent = gui,
	})
	tween(root, ti(0.5, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.5 })

	local field = Geo.Field(root, { ZIndex = 1, Density = 0.55, Solids = 0, Parallax = false })
	field:Fade(1, 2.5)
	local vig = Vignette(root, CYAN, { ZIndex = 2, Strength = 0.3, Radius = 0.5 })
	vig:Fade(0.2, ti(0.7, Enum.EasingStyle.Quad))

	local content = new("Frame", {
		Name = "Content", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, contentW, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 5, Parent = root,
	})
	list(content, 10, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	local emblem = new("Frame", { Name = "Emblem", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, emblemPx), LayoutOrder = 1, Parent = content })
	local outer = Geo.Solid(emblem, "ico", {
		Radius = emblemPx * 0.46, Color = CYAN_HOT, Thickness = 1.5, Opacity = 0.95, Dot = 4, SpinX = 0.35, SpinY = 0.55, SpinZ = 0.12,
	})
	local inner = Geo.Solid(emblem, "octa", {
		Radius = emblemPx * 0.22, Color = Color3.new(1, 1, 1), Thickness = 1.5, Opacity = 0.95, Dot = 3, SpinX = -0.6, SpinY = -0.8, SpinZ = 0.2,
	})
	local pose = { a = 0, s = 0.6, ga = 1, gs = 1 }

	new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 2, Parent = content })

	local title = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, FontFace = Fonts.Heavy, TextSize = compact and 17 or 21,
		Text = spaced(cfg.Title or "Singularity"), TextColor3 = Theme.Text, ZIndex = 6, Parent = content,
	})
	local credit = new("TextLabel", {
		Name = "Credit", Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 4, FontFace = Fonts.Mono, TextSize = 10,
		Text = CREDIT_TEXT, TextColor3 = Theme.Soft, ZIndex = 6, Parent = content,
	})
	connect(credit:GetPropertyChangedSignal("Text"), function()
		if credit.Text ~= CREDIT_TEXT then credit.Text = CREDIT_TEXT end
	end)
	local sub = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 5, FontFace = Fonts.Mono, TextSize = 10,
		Text = string.upper(cfg.Subtitle or "event horizon interface"), TextColor3 = CYAN_HOT, ZIndex = 6, Parent = content,
	})

	new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 8), LayoutOrder = 6, Parent = content })

	local track = new("Frame", {
		Size = UDim2.new(0, barW, 0, 2), BackgroundColor3 = Color3.fromRGB(70, 84, 96), BackgroundTransparency = 0.2,
		LayoutOrder = 7, ZIndex = 6, Parent = content,
	})
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = CYAN, ZIndex = 7, Parent = track })
	new("UIGradient", { Color = ColorSequence.new(CYAN_DEEP, CYAN_HOT), Parent = fill })
	local headGlow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = CYAN, BackgroundTransparency = 0.8, ZIndex = 7, Parent = fill,
	})
	corner(headGlow, 0, 1)
	local headDot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = CYAN_HOT, ZIndex = 8, Parent = fill,
	})
	corner(headDot, 0, 1)

	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, barW, 0, 14), LayoutOrder = 8, ZIndex = 6, Parent = content })
	local status = new("TextLabel", {
		Size = UDim2.new(0.8, 0, 1, 0), FontFace = Fonts.Mono, TextSize = 10, Text = "INITIALIZING",
		TextColor3 = Color3.fromRGB(190, 206, 216), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = row,
	})
	local pct = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.2, 0, 1, 0),
		FontFace = Fonts.Mono, TextSize = 10, Text = "0%", TextColor3 = CYAN, TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6, Parent = row,
	})

	local counter = Instance.new("NumberValue")
	counter.Parent = gui
	counter.Changed:Connect(function(v) pct.Text = string.format("%d%%", math.floor(v + 0.5)) end)

	local loader = { Gui = gui }
	local destroyed, closed = false, false

	FX.Ticker(function(dt)
		if destroyed then return false end
		local k = 1 - math.exp(-dt * 6)
		pose.a = pose.a + (pose.ga - pose.a) * k
		pose.s = pose.s + (pose.gs - pose.s) * k
		outer.alpha, outer.scale = pose.a, pose.s
		inner.alpha, inner.scale = pose.a, pose.s
		outer:Step(dt)
		inner:Step(dt)
	end)

	local function swapStatus(text)
		text = string.upper(text)
		if status.Text == text then return end
		task.spawn(function()
			tween(status, EASE.Fast, { TextTransparency = 1 })
			task.wait(0.15)
			if destroyed then return end
			status.Text = text
			status.Position = UDim2.fromOffset(0, 4)
			tween(status, EASE.Fast, { TextTransparency = 0, Position = UDim2.fromOffset(0, 0) })
		end)
	end

	function loader:Set(p, text, t)
		if destroyed then return end
		p = math.clamp(p, 0, 1)
		local info = TweenInfo.new(t or 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		tween(fill, info, { Size = UDim2.fromScale(p, 1) })
		tween(counter, info, { Value = p * 100 })
		vig:Fade(0.2 + 0.2 * p, info)
		if text then swapStatus(text) end
	end

	-- steps: strings or { Text = "...", Task = function() end, Weight = 1 }
	function loader:Run(steps, duration)
		steps = steps or DEFAULT_STEPS
		duration = duration or 4.5
		local n = #steps
		local weights, total = {}, 0
		for i, st in ipairs(steps) do
			local w = (type(st) == "table" and st.Weight) or (0.7 + math.random() * 0.6)
			weights[i] = w
			total = total + w
		end
		for i, st in ipairs(steps) do
			local isTable = type(st) == "table"
			local t = duration * weights[i] / total
			self:Set(i / n, isTable and st.Text or tostring(st), t)
			local started = os.clock()
			if isTable and type(st.Task) == "function" then safe(st.Task) end
			local remain = t - (os.clock() - started)
			if remain > 0 then task.wait(remain) end
		end
	end

	local function destroy()
		if destroyed then return end
		destroyed = true
		field:Destroy()
		counter:Destroy()
		gui:Destroy()
	end

	function loader:Close()
		if closed then return end
		closed = true
		self:Set(1, "Singularity reached", 0.25)
		task.wait(0.5)
		local out = ti(0.3, Enum.EasingStyle.Quad)
		tween(title, out, { TextTransparency = 1 })
		tween(credit, out, { TextTransparency = 1 })
		tween(sub, out, { TextTransparency = 1 })
		tween(status, out, { TextTransparency = 1 })
		tween(pct, out, { TextTransparency = 1 })
		tween(track, out, { BackgroundTransparency = 1 })
		tween(fill, out, { BackgroundTransparency = 1 })
		tween(headGlow, out, { BackgroundTransparency = 1 })
		tween(headDot, out, { BackgroundTransparency = 1 })
		pose.gs = 1.25
		task.wait(0.22)
		local wave = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
			Size = UDim2.fromOffset(emblemPx * 0.6, emblemPx * 0.6), ZIndex = 9, Parent = emblem,
		})
		corner(wave, 0, 1)
		local ws = stroke(wave, CYAN_HOT, 2, 0)
		tween(wave, ti(0.7), { Size = UDim2.fromOffset(emblemPx * 3.2, emblemPx * 3.2) })
		tween(ws, ti(0.7, Enum.EasingStyle.Quad), { Transparency = 1 })
		pose.ga, pose.gs = 0, 2.2
		vig:Fade(0.4, ti(0.2, Enum.EasingStyle.Quad))
		task.wait(0.35)
		tween(root, ti(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
		vig:Fade(0, ti(0.45, Enum.EasingStyle.Quad))
		field:Fade(0, 8)
		task.wait(0.5)
		destroy()
	end

	Cleanups[#Cleanups + 1] = destroy
	return loader
end

-- one call: build the loader, run it, close it (yields until finished)
function Singularity:Load(cfg)
	cfg = cfg or {}
	local loader = self:CreateLoader(cfg)
	loader:Run(cfg.Steps, cfg.Duration or 4.5)
	loader:Close()
end

------------------------------------------------------------------------
-- notifications
------------------------------------------------------------------------
local NotifyGui, NotifyHolder
local notifyCount = 0
local NotifyColors = {
	Success = Color3.fromRGB(110, 214, 150),
	Warn = Color3.fromRGB(255, 196, 76),
	Error = Color3.fromRGB(240, 82, 72),
}

local function ensureNotify()
	if NotifyGui and NotifyGui.Parent then return end
	NotifyGui = makeGui("SingularityNotify", 1000, false)
	local w = guiSize(NotifyGui).X < 600 and 250 or 290
	NotifyHolder = new("Frame", {
		Name = "Holder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, w, 1, -32), Parent = NotifyGui,
	})
	list(NotifyHolder, 8, { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right })
end

function Singularity:Notify(cfg)
	if self.Notifications == false then return end
	if type(cfg) == "string" then cfg = { Content = cfg } end
	cfg = cfg or {}
	ensureNotify()
	notifyCount = notifyCount + 1
	local dur = cfg.Duration or 4
	local color = NotifyColors[cfg.Type or ""] or Theme.Accent
	Sfx:Play(({ Success = "notify_success", Warn = "notify_warn", Error = "notify_error" })[cfg.Type or ""] or "notify_info")

	local slot = new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = notifyCount, Parent = NotifyHolder,
	})
	local card = new("Frame", {
		BackgroundColor3 = Theme.Panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(340, 0), Parent = slot,
	})
	corner(card, 6)
	stroke(card, Theme.Line, 1)
	local body = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card })
	pad(body, 16, 10, 12, 12)
	list(body, 3)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = Fonts.Bold, TextSize = 12,
		Text = cfg.Title or "Singularity", TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LayoutOrder = 1, Parent = body,
	})
	if cfg.Content then
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, Text = cfg.Content,
			TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true, LayoutOrder = 2, Parent = body,
		})
	end
	new("Frame", { Position = UDim2.fromOffset(0, 7), Size = UDim2.new(0, 2, 1, -14), BackgroundColor3 = color, Parent = card })
	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = color, BackgroundTransparency = 0.45, Parent = card,
	})

	tween(card, ti(0.4), { Position = UDim2.fromOffset(0, 0) })
	tween(bar, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })
	task.delay(dur, function()
		if not slot.Parent then return end
		tween(card, ti(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.fromOffset(340, 0) })
		task.wait(0.3)
		if not slot.Parent then return end
		slot.AutomaticSize = Enum.AutomaticSize.None
		slot.Size = UDim2.new(1, 0, 0, slot.AbsoluteSize.Y)
		tween(slot, ti(0.2, Enum.EasingStyle.Quad), { Size = UDim2.new(1, 0, 0, 0) })
		task.wait(0.22)
		slot:Destroy()
	end)
end

------------------------------------------------------------------------
-- keybind registry
------------------------------------------------------------------------
local Binds = {}
local Listening = false
local BINDABLE = { Toggle = true, Button = true } -- elements a single key can drive
local Features = {} -- every bindable element built inside a window tab

connect(UserInputService.InputBegan, function(input, gp)
	if Listening or gp then return end
	for _, b in ipairs(Binds) do b:_down(input) end
end)
connect(UserInputService.InputEnded, function(input)
	if Listening then return end
	for _, b in ipairs(Binds) do b:_up(input) end
end)

local function keyText(k)
	if not k then return "NONE" end
	local n = k.Name
	n = string.gsub(n, "^Left", "L")
	n = string.gsub(n, "^Right", "R")
	n = string.gsub(n, "MouseButton", "M")
	return n
end

------------------------------------------------------------------------
-- section + elements
------------------------------------------------------------------------
local Section = {}
Section.__index = Section

local function newRow(sec, height, class)
	sec._order = sec._order + 1
	local row = new(class or "Frame", {
		Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = sec._order, Parent = sec.Body,
	})
	-- the first row an element builds is its clickable row (used by the bind picker)
	if not sec._pendingRow then sec._pendingRow = row end
	return row
end

local function register(sec, cfg, el)
	el.Section = sec
	el.Name = cfg.Name or el.Name
	el.Flag = cfg.Flag
	el._row = sec._pendingRow
	sec._pendingRow = nil
	if BINDABLE[el.Type] and sec.Tab and sec.Tab.Window then Features[#Features + 1] = el end
	el.NoConfig = cfg.NoConfig
	if cfg.Flag then
		Singularity.Elements[cfg.Flag] = el
		Singularity.Flags[cfg.Flag] = el.Value
	end
end

local function commit(el, value)
	el.Value = value
	if el.Flag then Singularity.Flags[el.Flag] = value end
end

local function chevron(parent)
	local box = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -2, 0.5, 0), Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1, Parent = parent,
	})
	local function arm(x, rot)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 5), Size = UDim2.fromOffset(7, 1.5),
			Rotation = rot, BackgroundColor3 = Theme.Dim, Parent = box,
		})
		corner(f, 0, 0.5)
	end
	arm(3.5, 40)
	arm(8.5, -40)
	return box
end

-- Toggle ----------------------------------------------------------------
function Section:Toggle(cfg)
	cfg = cfg or {}
	local el = { Type = "Toggle", Value = cfg.Default == true }
	local row = newRow(self, 30, "TextButton")
	local label = new("TextLabel", {
		Size = UDim2.new(1, -44, 1, 0), Text = cfg.Name or "Toggle", TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Dim, Parent = row,
	})
	local track = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(32, 16),
		BackgroundColor3 = Theme.Track, Parent = row,
	})
	corner(track, 0, 1)
	local trackStroke = stroke(track, Theme.Line, 1)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Theme.Dim, Parent = track,
	})
	corner(knob, 0, 1)
	local hover = false

	local function render(info)
		local on = el.Value
		tween(track, info, { BackgroundColor3 = on and Theme.Deep or Theme.Track })
		tween(trackStroke, info, { Color = on and Theme.Accent or Theme.Line })
		tween(knob, info, {
			Position = on and UDim2.new(0, 19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = on and Theme.Hot or Theme.Dim,
		})
		tween(label, info, { TextColor3 = (on or hover) and Theme.Text or Theme.Dim })
	end

	function el:Set(v, silent)
		commit(self, v and true or false)
		render(EASE.Med)
		if not silent then safe(cfg.Callback, self.Value) end
	end
	function el:Get() return self.Value end
	function el:Encode() return self.Value end
	function el:Decode(v) if type(v) == "boolean" then self:Set(v) end end

	row.MouseEnter:Connect(function() hover = true render(EASE.Fast) end)
	row.MouseLeave:Connect(function() hover = false render(EASE.Fast) end)
	row.MouseButton1Down:Connect(function() tween(knob, EASE.Fast, { Size = UDim2.fromOffset(14, 10) }) end)
	row.MouseButton1Up:Connect(function() tween(knob, EASE.Fast, { Size = UDim2.fromOffset(10, 10) }) end)
	row.MouseLeave:Connect(function() tween(knob, EASE.Fast, { Size = UDim2.fromOffset(10, 10) }) end)
	row.Activated:Connect(function()
		el:Set(not el.Value)
		Sfx:Play(el.Value and "toggle_on" or "toggle_off")
	end)
	onAccent(function() render(EASE.Instant) end)

	register(self, cfg, el)
	return el
end

-- Slider ----------------------------------------------------------------
function Section:Slider(cfg)
	cfg = cfg or {}
	local min, max = cfg.Min or 0, cfg.Max or 100
	local inc = cfg.Increment or 1
	local suffix = cfg.Suffix or ""
	local decimals = 0
	local incStr = tostring(inc)
	local dot = string.find(incStr, ".", 1, true)
	if dot then decimals = #incStr - dot end

	local function snap(v)
		v = math.clamp(v, min, max)
		v = math.floor((v - min) / inc + 0.5) * inc + min
		v = tonumber(string.format("%." .. decimals .. "f", v))
		return math.clamp(v, min, max)
	end

	local el = { Type = "Slider", Value = snap(cfg.Default or min) }
	local page = self.Page
	local row = newRow(self, 42)
	local label = new("TextLabel", {
		Size = UDim2.new(1, -70, 0, 20), Text = cfg.Name or "Slider", TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Dim, Parent = row,
	})
	local valueLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 70, 0, 20),
		FontFace = Fonts.Mono, TextSize = 11, TextColor3 = Theme.Accent, TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
	})
	onAccent(function(a) valueLabel.TextColor3 = a end)
	local hit = new("TextButton", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 18), Parent = row })
	local track = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Theme.Track, Parent = hit,
	})
	corner(track, 0, 1)
	stroke(track, Theme.Line, 1)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Accent, Parent = track })
	corner(fill, 0, 1)
	local fg = new("UIGradient", { Parent = fill })
	onAccent(function(a, h, d)
		fill.BackgroundColor3 = a
		fg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, d), ColorSequenceKeypoint.new(1, a) })
	end)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Theme.Hot, ZIndex = 2, Parent = track,
	})
	corner(knob, 0, 1)
	local knobStroke = stroke(knob, Theme.Accent, 1.5)
	local knobScale = new("UIScale", { Scale = 0.8, Parent = knob })
	onAccent(function(a, h) knob.BackgroundColor3 = h knobStroke.Color = a end)

	local dragging, hover = false, false
	local function render(info)
		local p = (max > min) and (el.Value - min) / (max - min) or 0
		tween(fill, info, { Size = UDim2.fromScale(p, 1) })
		tween(knob, info, { Position = UDim2.fromScale(p, 0.5) })
		valueLabel.Text = string.format("%." .. decimals .. "f", el.Value) .. suffix
	end
	local function restScale()
		tween(knobScale, EASE.Fast, { Scale = (dragging or hover) and 1.1 or 0.8 })
		tween(label, EASE.Fast, { TextColor3 = (dragging or hover) and Theme.Text or Theme.Dim })
	end
	local function fromX(x)
		local w = track.AbsoluteSize.X
		if w <= 0 then return end
		local p = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
		local v = snap(min + (max - min) * p)
		if v ~= el.Value then
			commit(el, v)
			render(EASE.Drag)
			Sfx:Play("slider", 0.8 + ((max > min) and (v - min) / (max - min) or 0) * 0.7)
			safe(cfg.Callback, v)
		end
	end

	trackDrag(hit, {
		Begin = function(input)
			dragging = true
			if page then page.ScrollingEnabled = false end
			restScale()
			fromX(input.Position.X)
		end,
		Move = function(i) fromX(i.Position.X) end,
		End = function()
			dragging = false
			if page then page.ScrollingEnabled = true end
			restScale()
		end,
	})
	hit.MouseEnter:Connect(function() hover = true restScale() end)
	hit.MouseLeave:Connect(function() hover = false restScale() end)

	function el:Set(v, silent)
		commit(self, snap(tonumber(v) or min))
		render(EASE.Med)
		if not silent then safe(cfg.Callback, self.Value) end
	end
	function el:Get() return self.Value end
	function el:Encode() return self.Value end
	function el:Decode(v) if type(v) == "number" then self:Set(v) end end

	render(EASE.Instant)
	register(self, cfg, el)
	return el
end

-- Dropdown --------------------------------------------------------------
function Section:Dropdown(cfg)
	cfg = cfg or {}
	local multi = cfg.Multi == true
	local options = cfg.Options or {}
	local el = { Type = "Dropdown", Multi = multi, Options = options }
	local selected = {}
	local open = false
	local buttons = {}

	local function multiValue()
		local out = {}
		for _, o in ipairs(options) do
			if selected[o] then out[#out + 1] = o end
		end
		return out
	end
	if multi then
		for _, v in ipairs(type(cfg.Default) == "table" and cfg.Default or {}) do selected[v] = true end
		el.Value = multiValue()
	else
		el.Value = cfg.Default
	end

	local row = newRow(self, 30)
	row.ClipsDescendants = true
	local header = new("TextButton", { Size = UDim2.new(1, 0, 0, 30), Parent = row })
	local label = new("TextLabel", {
		Size = UDim2.new(0.45, 0, 1, 0), Text = cfg.Name or "Dropdown", TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Dim, Parent = header,
	})
	local valueLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 0), Size = UDim2.new(0.55, -20, 1, 0),
		FontFace = Fonts.Mono, TextSize = 11, TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = header,
	})
	local arrow = chevron(header)

	local box = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Theme.Track,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Accent, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = row,
	})
	corner(box, 5)
	stroke(box, Theme.Line, 1)
	pad(box, 4, 4, 4, 4)
	list(box, 2)
	onAccent(function(a) box.ScrollBarImageColor3 = a end)

	local function boxHeight()
		local n = math.min(#options, 6)
		return n > 0 and (n * 28 - 2 + 8) or 8
	end
	local function isSelected(o)
		if multi then return selected[o] == true end
		return el.Value == o
	end
	local function display()
		if multi then
			local v = multiValue()
			return #v == 0 and "None" or table.concat(v, ", ")
		end
		return el.Value ~= nil and tostring(el.Value) or "None"
	end
	local function refresh()
		for o, b in pairs(buttons) do
			local on = isSelected(o)
			tween(b.btn, EASE.Fast, { TextColor3 = on and Theme.Accent or Theme.Dim })
			tween(b.mark, EASE.Fast, { BackgroundTransparency = on and 0 or 1 })
		end
		valueLabel.Text = display()
	end
	local function resize()
		local h = boxHeight()
		tween(box, EASE.Med, { Size = UDim2.new(1, 0, 0, open and h or 0) })
		tween(row, EASE.Med, { Size = UDim2.new(1, 0, 0, open and (34 + h + 2) or 30) })
		tween(arrow, EASE.Med, { Rotation = open and 180 or 0 })
	end
	local function setOpen(v)
		open = v
		resize()
	end

	local build
	local function choose(o)
		if multi then
			selected[o] = (not selected[o]) or nil
			commit(el, multiValue())
			refresh()
			safe(cfg.Callback, el.Value)
		else
			el:Set(o)
			setOpen(false)
		end
	end
	function build()
		for _, c in ipairs(box:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		buttons = {}
		for i, o in ipairs(options) do
			local btn = new("TextButton", {
				Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, Text = tostring(o), TextSize = 12,
				TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = Theme.Hover, Parent = box,
			})
			corner(btn, 4)
			pad(btn, 8, 0, 8, 0)
			local mark = new("Frame", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, Parent = btn,
			})
			corner(mark, multi and 1 or 0, multi and 0 or 1)
			onAccent(function(a) mark.BackgroundColor3 = a end)
			btn.MouseEnter:Connect(function() tween(btn, EASE.Fast, { BackgroundTransparency = 0.5 }) end)
			btn.MouseLeave:Connect(function() tween(btn, EASE.Fast, { BackgroundTransparency = 1 }) end)
			btn.Activated:Connect(function()
				choose(o)
				Sfx:Play("select")
			end)
			buttons[o] = { btn = btn, mark = mark }
		end
		refresh()
	end

	function el:Set(v, silent)
		if multi then
			selected = {}
			for _, x in ipairs(type(v) == "table" and v or {}) do selected[x] = true end
			commit(self, multiValue())
		else
			commit(self, v)
		end
		refresh()
		if not silent then safe(cfg.Callback, self.Value) end
	end
	function el:Get() return self.Value end
	function el:SetOptions(list2)
		options = list2 or {}
		self.Options = options
		if multi then
			commit(self, multiValue())
		elseif self.Value ~= nil then
			local found = false
			for _, o in ipairs(options) do if o == self.Value then found = true end end
			if not found then commit(self, nil) end
		end
		build()
		if open then resize() end
	end
	function el:Encode() return self.Value end
	function el:Decode(v) if v ~= nil then self:Set(v) end end

	header.Activated:Connect(function()
		setOpen(not open)
		Sfx:Play(open and "dd_open" or "dd_close")
	end)
	header.MouseEnter:Connect(function() tween(label, EASE.Fast, { TextColor3 = Theme.Text }) end)
	header.MouseLeave:Connect(function() tween(label, EASE.Fast, { TextColor3 = Theme.Dim }) end)

	build()
	register(self, cfg, el)
	return el
end

-- Keybind ---------------------------------------------------------------
local MODES = { "Toggle", "Hold", "Press" }

function Section:Keybind(cfg)
	cfg = cfg or {}
	local el = { Type = "Keybind", Name = cfg.Name, Key = cfg.Default, Mode = cfg.Mode or "Toggle", Value = false }
	local listening = false
	local ignoreCycleUntil = 0

	local row = newRow(self, 30)
	new("TextLabel", {
		Size = UDim2.new(1, -110, 1, 0), Text = cfg.Name or "Keybind", TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Dim, Parent = row,
	})
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = row,
	})
	list(holder, 8, {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local modeLabel = new("TextLabel", {
		Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X, FontFace = Fonts.Mono, TextSize = 9,
		TextColor3 = Theme.Faint, LayoutOrder = 1, Parent = holder,
	})
	local chip = new("TextButton", {
		Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X, FontFace = Fonts.Mono, TextSize = 11,
		BackgroundColor3 = Theme.Track, BackgroundTransparency = 0, LayoutOrder = 2, Parent = holder,
	})
	corner(chip, 4)
	pad(chip, 8, 0, 8, 0)
	local chipStroke = stroke(chip, Theme.Line, 1)

	local function refresh()
		chip.Text = listening and "..." or keyText(el.Key)
		modeLabel.Text = string.upper(string.sub(el.Mode, 1, 3))
		tween(chipStroke, EASE.Fast, { Color = listening and Theme.Accent or Theme.Line })
		tween(chip, EASE.Fast, { TextColor3 = (listening or el.Key) and Theme.Text or Theme.Faint })
	end

	local function matches(input)
		return el.Key ~= nil and (input.KeyCode == el.Key or input.UserInputType == el.Key)
	end
	function el:_down(input)
		if not matches(input) then return end
		if self.Mode == "Toggle" then
			commit(self, not self.Value)
			safe(cfg.Callback, self.Value)
		elseif self.Mode == "Hold" then
			commit(self, true)
			safe(cfg.Callback, true)
		else
			safe(cfg.Callback, true)
		end
	end
	function el:_up(input)
		if self.Mode == "Hold" and matches(input) then
			commit(self, false)
			safe(cfg.Callback, false)
		end
	end

	function el:SetKey(key, silent)
		self.Key = key
		if self.Mode ~= "Toggle" then commit(self, false) end
		refresh()
		if not silent then safe(cfg.Changed, key) end
	end
	function el:SetMode(mode)
		self.Mode = mode
		commit(self, false)
		refresh()
	end
	function el:Set(key, silent) self:SetKey(key, silent) end
	function el:Get() return self.Key end
	function el:Encode()
		return { Key = self.Key and self.Key.Name or nil, Kind = self.Key and tostring(self.Key.EnumType) or nil, Mode = self.Mode }
	end
	function el:Decode(v)
		if type(v) ~= "table" then return end
		if v.Mode then self:SetMode(v.Mode) end
		if v.Key then
			local enum = (v.Kind == "UserInputType") and Enum.UserInputType or Enum.KeyCode
			local ok, item = pcall(function() return enum[v.Key] end)
			if ok and item then self:SetKey(item) end
		else
			self:SetKey(nil)
		end
	end

	chip.Activated:Connect(function()
		if listening then return end
		Sfx:Play("click")
		listening = true
		Listening = true
		refresh()
		task.spawn(function()
			while true do
				local input = UserInputService.InputBegan:Wait()
				local t = input.UserInputType
				if t == Enum.UserInputType.Keyboard then
					if input.KeyCode == Enum.KeyCode.Escape then el:SetKey(nil) else el:SetKey(input.KeyCode) end
					break
				elseif t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
					ignoreCycleUntil = os.clock() + 0.5
					el:SetKey(t)
					break
				elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
					break
				end
			end
			task.wait()
			listening = false
			Listening = false
			refresh()
		end)
	end)
	chip.MouseButton2Click:Connect(function()
		if listening or os.clock() < ignoreCycleUntil then return end
		local idx = table.find(MODES, el.Mode) or 1
		el:SetMode(MODES[idx % #MODES + 1])
	end)

	Binds[#Binds + 1] = el
	if Singularity._bindsChanged then Singularity._bindsChanged() end
	refresh()
	register(self, cfg, el)
	return el
end

-- ColorPicker -----------------------------------------------------------
local function toHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

function Section:ColorPicker(cfg)
	cfg = cfg or {}
	local start = cfg.Default or Color3.fromRGB(255, 132, 38)
	local h, s, v = Color3.toHSV(start)
	local el = { Type = "ColorPicker", Value = start }
	local page = self.Page
	local open = false
	local PH = 132

	local row = newRow(self, 30)
	row.ClipsDescendants = true
	local header = new("TextButton", { Size = UDim2.new(1, 0, 0, 30), Parent = row })
	local label = new("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0), Text = cfg.Name or "Color", TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Dim, Parent = header,
	})
	local swatch = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(30, 14),
		BackgroundColor3 = start, Parent = header,
	})
	corner(swatch, 4)
	stroke(swatch, Theme.Line, 1)

	local panel = new("Frame", { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, PH), BackgroundTransparency = 1, Parent = row })
	local sv = new("TextButton", {
		Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, -24, 0, 96), BackgroundColor3 = Color3.fromHSV(h, 1, 1), Parent = panel,
	})
	corner(sv, 4)
	local white = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sv })
	corner(white, 4)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = white })
	local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv })
	corner(black, 4)
	new("UIGradient", {
		Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }), Parent = black,
	})
	local cursor = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 3, Parent = sv,
	})
	corner(cursor, 0, 1)
	stroke(cursor, Color3.new(1, 1, 1), 1.5)

	local hue = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(14, 96),
		BackgroundColor3 = Color3.new(1, 1, 1), Parent = panel,
	})
	corner(hue, 4)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)), ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)), ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)), ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)),
		}),
		Parent = hue,
	})
	local hueMark = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 6, 0, 4), BackgroundTransparency = 1, ZIndex = 3, Parent = hue,
	})
	corner(hueMark, 2)
	stroke(hueMark, Color3.new(1, 1, 1), 1.5)

	local hexBox = new("TextBox", {
		Position = UDim2.fromOffset(0, 106), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Theme.Track, BackgroundTransparency = 0,
		FontFace = Fonts.Mono, TextSize = 11, ClearTextOnFocus = false, Text = toHex(start), Parent = panel,
	})
	corner(hexBox, 4)
	local hexStroke = stroke(hexBox, Theme.Line, 1)

	local function refresh(silent)
		local c = Color3.fromHSV(h, s, v)
		el.Value = c
		if el.Flag then Singularity.Flags[el.Flag] = c end
		swatch.BackgroundColor3 = c
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		cursor.Position = UDim2.fromScale(s, 1 - v)
		hueMark.Position = UDim2.fromScale(0.5, h)
		if not hexBox:IsFocused() then hexBox.Text = toHex(c) end
		if not silent then safe(cfg.Callback, c) end
	end

	local function dragRegion(hit, apply)
		trackDrag(hit, {
			Begin = function(input)
				if page then page.ScrollingEnabled = false end
				apply(input.Position)
			end,
			Move = function(i) apply(i.Position) end,
			End = function() if page then page.ScrollingEnabled = true end end,
		})
	end
	dragRegion(sv, function(pos)
		local sz, ap = sv.AbsoluteSize, sv.AbsolutePosition
		s = math.clamp((pos.X - ap.X) / sz.X, 0, 1)
		v = 1 - math.clamp((pos.Y - ap.Y) / sz.Y, 0, 1)
		refresh()
	end)
	dragRegion(hue, function(pos)
		local sz, ap = hue.AbsoluteSize, hue.AbsolutePosition
		h = math.clamp((pos.Y - ap.Y) / sz.Y, 0, 1)
		refresh()
	end)

	hexBox.Focused:Connect(function() tween(hexStroke, EASE.Fast, { Color = Theme.Accent }) end)
	hexBox.FocusLost:Connect(function()
		tween(hexStroke, EASE.Fast, { Color = Theme.Line })
		local r, g, b = string.match(hexBox.Text, "^#?(%x%x)(%x%x)(%x%x)$")
		if r then
			h, s, v = Color3.toHSV(Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)))
		end
		refresh()
	end)

	header.Activated:Connect(function()
		open = not open
		Sfx:Play(open and "dd_open" or "dd_close")
		tween(row, EASE.Med, { Size = UDim2.new(1, 0, 0, open and (34 + PH + 2) or 30) })
	end)
	header.MouseEnter:Connect(function() tween(label, EASE.Fast, { TextColor3 = Theme.Text }) end)
	header.MouseLeave:Connect(function() tween(label, EASE.Fast, { TextColor3 = Theme.Dim }) end)

	function el:Set(c, silent)
		if typeof(c) ~= "Color3" then return end
		h, s, v = Color3.toHSV(c)
		refresh(silent)
	end
	function el:Get() return self.Value end
	function el:Encode() return { self.Value.R, self.Value.G, self.Value.B } end
	function el:Decode(t)
		if type(t) == "table" and #t == 3 then self:Set(Color3.new(t[1], t[2], t[3])) end
	end

	register(self, cfg, el)
	refresh(true)
	return el
end

-- Button ----------------------------------------------------------------
function Section:Button(cfg)
	cfg = cfg or {}
	local el = { Type = "Button" }
	local row = newRow(self, 28)
	local btn = new("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Track, BackgroundTransparency = 0,
		Text = cfg.Name or "Button", TextSize = 12, TextColor3 = Theme.Text, Parent = row,
	})
	corner(btn, 4)
	local bs = stroke(btn, Theme.Line, 1)
	local sc = new("UIScale", { Parent = btn })
	local flash = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, Parent = btn,
	})
	corner(flash, 4)
	onAccent(function(a) flash.BackgroundColor3 = a end)

	btn.MouseEnter:Connect(function()
		tween(bs, EASE.Fast, { Color = Theme.Accent })
		tween(btn, EASE.Fast, { BackgroundColor3 = Theme.Hover })
	end)
	btn.MouseLeave:Connect(function()
		tween(bs, EASE.Fast, { Color = Theme.Line })
		tween(btn, EASE.Fast, { BackgroundColor3 = Theme.Track })
		tween(sc, EASE.Fast, { Scale = 1 })
	end)
	btn.MouseButton1Down:Connect(function() tween(sc, EASE.Fast, { Scale = 0.97 }) end)
	btn.MouseButton1Up:Connect(function() tween(sc, EASE.Pop, { Scale = 1 }) end)
	btn.Activated:Connect(function()
		Sfx:Play("click")
		flash.BackgroundTransparency = 0.75
		tween(flash, ti(0.4), { BackgroundTransparency = 1 })
		safe(cfg.Callback)
	end)

	function el:SetText(t) btn.Text = t end
	function el:Press() Sfx:Play("click") safe(cfg.Callback) end
	register(self, cfg, el)
	return el
end

-- Textbox ---------------------------------------------------------------
function Section:Textbox(cfg)
	cfg = cfg or {}
	local el = { Type = "Textbox", Value = cfg.Default or "" }
	local row = newRow(self, 30)
	new("TextLabel", {
		Size = UDim2.new(0.4, 0, 1, 0), Text = cfg.Name or "Textbox", TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Dim, Parent = row,
	})
	local box = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.58, 0, 0, 22),
		BackgroundColor3 = Theme.Track, BackgroundTransparency = 0, FontFace = Fonts.Mono, TextSize = 11,
		Text = el.Value, PlaceholderText = cfg.Placeholder or "", PlaceholderColor3 = Theme.Faint,
		ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
	})
	corner(box, 4)
	pad(box, 8, 0, 8, 0)
	local bs = stroke(box, Theme.Line, 1)
	box.Focused:Connect(function() tween(bs, EASE.Fast, { Color = Theme.Accent }) end)
	box.FocusLost:Connect(function()
		tween(bs, EASE.Fast, { Color = Theme.Line })
		commit(el, box.Text)
		safe(cfg.Callback, box.Text)
	end)

	function el:Set(t, silent)
		t = tostring(t or "")
		commit(self, t)
		box.Text = t
		if not silent then safe(cfg.Callback, t) end
	end
	function el:Get() return self.Value end
	function el:Encode() return self.Value end
	function el:Decode(v) if type(v) == "string" then self:Set(v) end end

	register(self, cfg, el)
	return el
end

-- Label / Divider -------------------------------------------------------
function Section:Label(text)
	self._order = self._order + 1
	local l = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = text or "", TextSize = 12,
		TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true, LayoutOrder = self._order, Parent = self.Body,
	})
	local el = { Type = "Label" }
	function el:Set(t) l.Text = t end
	return el
end

function Section:Divider()
	local row = newRow(self, 9)
	self._pendingRow = nil
	new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Line, Parent = row,
	})
end

------------------------------------------------------------------------
-- pages, tabs and sections
------------------------------------------------------------------------
local Tab = {}
Tab.__index = Tab

-- a scrolling two-column page; narrow widths fold everything into one column
local function makePage(parent, name)
	local page = new("ScrollingFrame", {
		Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent,
		ScrollBarImageTransparency = 0.35, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, Parent = parent,
	})
	onAccent(function(a) page.ScrollBarImageColor3 = a end)
	pad(page, 2, 4, 10, 14)
	local left = new("Frame", {
		Name = "Left", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(0.5, -7, 0, 0), Parent = page,
	})
	list(left, 12)
	local right = new("Frame", {
		Name = "Right", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 7, 0, 0), Size = UDim2.new(0.5, -7, 0, 0), Parent = page,
	})
	list(right, 12)
	return page, left, right
end

local function newPane(host, name)
	local page, left, right = makePage(host, name)
	return setmetatable({ Name = name, Page = page, Left = left, Right = right, _colOrder = {}, _sections = {}, _single = false }, Tab)
end

function Tab:_reflow(single)
	if self._single == single then return end
	self._single = single
	self.Left.Size = single and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -7, 0, 0)
	self.Right.Visible = not single
	for _, s in ipairs(self._sections) do
		if single then
			s.box.Parent = self.Left
			s.box.LayoutOrder = (s.side == "Right" and 1000 or 0) + s.order
		else
			s.box.Parent = (s.side == "Right") and self.Right or self.Left
			s.box.LayoutOrder = s.order
		end
	end
end

function Tab:CreateSection(name, side)
	side = (side == "Right") and "Right" or "Left"
	local col = (side == "Right") and self.Right or self.Left
	self._colOrder[side] = (self._colOrder[side] or 0) + 1
	local order = self._colOrder[side]
	local box = new("Frame", {
		Name = name, BackgroundColor3 = Theme.Glass, BackgroundTransparency = 0.34,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = col,
	})
	corner(box, 12)
	local edge = stroke(box, Theme.Line, 1, 0.45)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.3) }),
		Parent = box,
	})
	pad(box, 14, 8, 14, 12)
	list(box, 4)

	local head = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 0, Parent = box })
	local pip = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Theme.Accent, Parent = head,
	})
	corner(pip, 0, 1)
	onAccent(function(a) pip.BackgroundColor3 = a end)
	new("TextLabel", {
		Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -16, 1, 0), FontFace = Fonts.Bold, TextSize = 13,
		Text = name, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = head,
	})

	-- cursor reaction: the border brightens while the pointer is over a card
	box.MouseEnter:Connect(function() tween(edge, EASE.Med, { Transparency = 0.05, Color = Theme.Frost }) end)
	box.MouseLeave:Connect(function() tween(edge, EASE.Slow, { Transparency = 0.45, Color = Theme.Line }) end)

	self._sections[#self._sections + 1] = { box = box, side = side, order = order }
	if self._single then
		box.Parent = self.Left
		box.LayoutOrder = (side == "Right" and 1000 or 0) + order
	end
	return setmetatable({ Body = box, Page = self.Page, Tab = self, _order = 0 }, Section)
end

------------------------------------------------------------------------
-- window
------------------------------------------------------------------------
local Window = {}
Window.__index = Window

local SECTION_NAMES = { "Main", "Settings", "Keybind Manager", "Config Manager" }
local SECTION_SHORT = { "Main", "Settings", "Keybinds", "Configs" }

local textTok = setmetatable({}, { __mode = "k" })
local function swapText(label, text)
	if label.Text == text then return end
	local tok = (textTok[label] or 0) + 1
	textTok[label] = tok
	tween(label, EASE.Fast, { TextTransparency = 1 })
	task.delay(0.14, function()
		if textTok[label] ~= tok or not label.Parent then return end
		label.Text = text
		tween(label, EASE.Med, { TextTransparency = 0 })
	end)
end

local function snap(inst, props)
	cancelTweens(inst)
	for k, v in pairs(props) do inst[k] = v end
end

-- every visual state of a rail button comes from one place, so tweens never fight each other
local function applyPill(tab, info)
	local on, act, hov = tab.Shown, tab.Active, tab.Hover
	local ink = act and Theme.Hot or (hov and Theme.Text or Theme.Soft)
	tween(tab.Face, info, {
		BackgroundColor3 = act and Theme.Deep or Theme.Glass,
		BackgroundTransparency = on and (act and 0.04 or 0.1) or 1,
	})
	tween(tab.Slab, info, { BackgroundTransparency = on and 0.15 or 1 })
	tween(tab.Rim, info, {
		Color = act and Theme.Accent or (hov and Theme.Frost or Theme.Line),
		Transparency = on and ((act or hov) and 0 or 0.15) or 1,
	})
	tween(tab.Icon, info, { ImageColor3 = ink, ImageTransparency = on and 0 or 1 })
	tween(tab.Glyph, info, { TextColor3 = ink, TextTransparency = on and 0 or 1 })
	tween(tab.GlyphRing, info, { Color = ink, Transparency = on and 0.3 or 1 })
	tween(tab.Pip, info, { Size = UDim2.fromOffset(3, (on and act) and 20 or 0), BackgroundTransparency = on and 0 or 1 })
	tween(tab.Halo, info, { BackgroundTransparency = on and (act and 0.82 or (hov and 0.92 or 1)) or 1 })
end

-- a key bound to a toggle or a button picked in the Main section
local function newFeatureBind(target, key, mode)
	local rec = { Type = "Feature", Name = target.Name or "Feature", Target = target, Key = key, Mode = mode or "Toggle" }
	local function matches(input)
		return rec.Key ~= nil and (input.KeyCode == rec.Key or input.UserInputType == rec.Key)
	end
	function rec:_down(input)
		if not matches(input) then return end
		local t = self.Target
		if t.Type == "Button" then
			t:Press()
		elseif self.Mode == "Hold" then
			t:Set(true, false)
			Sfx:Play("toggle_on")
		else
			t:Set(not t.Value, false)
			Sfx:Play(t.Value and "toggle_on" or "toggle_off")
		end
	end
	function rec:_up(input)
		if self.Mode == "Hold" and self.Target.Type == "Toggle" and matches(input) then
			self.Target:Set(false, false)
		end
	end
	function rec:SetKey(k) self.Key = k end
	function rec:SetMode(m) self.Mode = m end
	function rec:Get() return self.Key end
	return rec
end

function Singularity:CreateWindow(cfg)
	cfg = cfg or {}
	local gui = makeGui("SingularityUI", 500, true)
	local vp = guiSize(gui)
	local compact = vp.X < 760 or vp.Y < 520
	local BTN = compact and 40 or 46            -- rail button size
	local EDGE = compact and 10 or 18           -- distance from the screen edges
	local BAR_H = compact and 36 or 42
	local TOP = EDGE + BAR_H + (compact and 8 or 14)
	local RAIL_OUT = BTN + EDGE + 30
	local minW, minH = compact and 340 or 560, compact and 230 or 340

	local function maxSize()
		local g = guiSize(gui)
		return math.max(g.X - (BTN + EDGE + 14) * 2, minW), math.max(g.Y - TOP - EDGE - 6, minH)
	end
	local function fit(w, h)
		local mw, mh = maxSize()
		return math.floor(math.clamp(w, minW, mw)), math.floor(math.clamp(h, minH, mh))
	end
	local g0 = guiSize(gui)
	local W, H = fit(cfg.Width or g0.X * 0.7, cfg.Height or g0.Y * 0.76)

	local window = setmetatable({
		Gui = gui, Tabs = {}, Visible = false, ToggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift,
		Compact = compact, Section = 1, _announced = false, Size = Vector2.new(W, H), DefaultSize = Vector2.new(W, H),
		Title = cfg.Title or "Singularity",
	}, Window)

	------------------------------------------------------------------
	-- full-screen backdrop (own ScreenGui, sits behind the interface)
	------------------------------------------------------------------
	local bgGui = makeGui("SingularityBackdrop", 400, true)
	local dim = new("Frame", {
		Name = "Dim", BackgroundColor3 = Color3.fromRGB(9, 10, 13), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = bgGui,
	})
	-- the game stays visible and only slightly darkened, with the geometry field over it
	local field = Geo.Field(bgGui, { ZIndex = 2, Density = 1.2, Solids = 10 })
	local function showBackdrop(on, info)
		tween(dim, info, { BackgroundTransparency = on and 0.82 or 1 })
		field:Fade(on and 1 or 0, on and 4 or 7)
	end
	Singularity._onQuality = function(q) field:SetQuality(q) end

	-- no background blur: the scene stays sharp and the vignette frames it
	window.BlurAmount = 0
	function window:SetBlur() end -- kept so existing scripts don't error; blur is disabled

	------------------------------------------------------------------
	-- the window: one glass body, sections slide inside a clipped viewport
	------------------------------------------------------------------
	local userScale = 1
	local root = new("Frame", {
		Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, (TOP - EDGE) / 2),
		Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, Visible = false, Parent = gui,
	})
	local rootScale = new("UIScale", { Parent = root })
	local stage = new("Frame", {
		Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 26),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root,
	})
	local popScale = new("UIScale", { Scale = 0.9, Parent = stage })

	local shadowSlabs = {}
	for i = 1, 5 do
		local s = new("Frame", {
			Name = "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 10 + i * 3),
			Size = UDim2.new(1, i * 12, 1, i * 12), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
			ZIndex = 0, Parent = stage,
		})
		corner(s, 20 + i * 6)
		shadowSlabs[i] = { f = s, t = 0.93 + i * 0.005 }
	end
	-- a dark strip under the body reads as the slab's thickness
	local slab = new("Frame", {
		Name = "Slab", Position = UDim2.fromOffset(0, 7), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(3, 4, 8),
		BackgroundTransparency = 1, ZIndex = 1, Parent = stage,
	})
	corner(slab, 18)
	local body = FX.Glass(stage, 18, { Name = "Body", Color = Color3.fromRGB(8, 10, 16), Transparency = 1, ZIndex = 2 })
	local rim = FX.RimStroke(body, 1.4, 18, 1, function() return window.Visible end)
	local viewport = new("Frame", {
		Name = "Viewport", BackgroundTransparency = 1, ClipsDescendants = false, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = stage,
	})

	local function limitsRoot()
		local g = guiSize(gui)
		local s = rootScale.Scale
		local hw, hh = window.Size.X * s / 2, window.Size.Y * s / 2
		return g, 150 - hw, EDGE + BAR_H + 6 + hh, g.X - 150 + hw, g.Y - 70 + hh
	end

	local panels = {}
	local function makePanel(idx, title, subtitle)
		local holder = new("Frame", {
			Name = SECTION_NAMES[idx], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = viewport,
		})
		local sc = new("UIScale", { Parent = holder })

		-- the card is the black box: it lives on the panel, so it travels with it
		local shadows = {}
		for i = 1, 5 do
			local sh = new("Frame", {
				Name = "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 10 + i * 3),
				Size = UDim2.new(1, i * 12, 1, i * 12), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
				ZIndex = 0, Parent = holder,
			})
			corner(sh, 20 + i * 6)
			shadows[i] = { f = sh, t = 0.93 + i * 0.005 }
		end
		local slabF = new("Frame", {
			Name = "Slab", Position = UDim2.fromOffset(0, 7), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(3, 4, 8),
			BackgroundTransparency = 1, ZIndex = 0, Parent = holder,
		})
		corner(slabF, 18)
		local card = FX.Glass(holder, 18, { Name = "Card", Color = Color3.fromRGB(8, 10, 16), Transparency = 1, ZIndex = 1 })
		local cardRim = FX.RimStroke(card, 1.4, 18, 1)

		local head = new("Frame", { Name = "Header", BackgroundTransparency = 1, Active = true, Size = UDim2.new(1, 0, 0, 62), ZIndex = 3, Parent = holder })
		local titleLabel = new("TextLabel", {
			Position = UDim2.fromOffset(26, 12), Size = UDim2.new(0.6, 0, 0, 26), FontFace = Fonts.Bold,
			TextSize = compact and 18 or 21, Text = title, TextXAlignment = Enum.TextXAlignment.Left, Name = "Title", ZIndex = 4, Parent = head,
		})
		local subLabel = new("TextLabel", {
			Position = UDim2.fromOffset(26, 38), Size = UDim2.new(0.7, 0, 0, 16), TextSize = 11, Text = subtitle or "",
			TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left, Name = "Subtitle", ZIndex = 4, Parent = head,
		})
		makeDraggable(head, root, limitsRoot)
		new("Frame", {
			Name = "Rule", Position = UDim2.fromOffset(20, 62), Size = UDim2.new(1, -40, 0, 1), BackgroundColor3 = Theme.Line,
			BackgroundTransparency = 0.55, ZIndex = 4, Parent = holder,
		})
		local host = new("Frame", {
			Name = "Host", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(20, 66),
			Size = UDim2.new(1, -40, 1, -86), ZIndex = 4, Parent = holder,
		})
		-- the veil dims a section while it slides away and lifts as it arrives
		local veil = new("Frame", {
			Name = "Veil", BackgroundColor3 = Theme.Panel, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = holder,
		})
		corner(veil, 18)
		local p = { idx = idx, holder = holder, scale = sc, veil = veil, host = host, head = head, title = titleLabel, subtitle = subLabel, token = 0,
			card = card, cardRim = cardRim, slab = slabF, shadows = shadows }
		panels[idx] = p
		return p
	end

	local pMain = makePanel(1, "Main", "")
	pMain.title.Text = window.Title
	local pSet = makePanel(2, "Settings", "Interface, audio and visuals")
	local pKeys = makePanel(3, "Keybind Manager", "Every bind in one place")
	local pCfg = makePanel(4, "Config Manager", "Save, load and share setups")

	local function snapAll(on)
		for _, p in pairs(panels) do
			snap(p.card, { BackgroundTransparency = on and 0.14 or 1 })
			snap(p.cardRim, { Transparency = on and 0.4 or 1 })
			snap(p.slab, { BackgroundTransparency = on and 0.3 or 1 })
			for _, s in ipairs(p.shadows) do snap(s.f, { BackgroundTransparency = on and s.t or 1 }) end
		end
		snap(popScale, { Scale = on and 1 or 0.9 })
		snap(stage, { Position = on and UDim2.fromScale(0.5, 0.5) or UDim2.new(0.5, 0, 0.5, 26) })
		snap(panels[window.Section].veil, { BackgroundTransparency = on and 1 or 0.6 })
	end
	local OPEN_POP = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local function setShown(on, info, popInfo)
		for _, p in pairs(panels) do
			tween(p.card, info, { BackgroundTransparency = on and 0.14 or 1 })
			tween(p.cardRim, info, { Transparency = on and 0.4 or 1 })
			tween(p.slab, info, { BackgroundTransparency = on and 0.3 or 1 })
			for _, s in ipairs(p.shadows) do tween(s.f, info, { BackgroundTransparency = on and s.t or 1 }) end
		end
		tween(popScale, popInfo, { Scale = on and 1 or 0.92 })
		tween(stage, popInfo, { Position = on and UDim2.fromScale(0.5, 0.5) or UDim2.new(0.5, 0, 0.5, 18) })
		tween(panels[window.Section].veil, info, { BackgroundTransparency = on and 1 or 0.6 })
	end

	-- panes -----------------------------------------------------------
	local setPane = newPane(pSet.host, "Settings")
	setPane.Page.Visible = true
	local keysHost = new("ScrollingFrame", {
		Name = "Binds", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent,
		ScrollBarImageTransparency = 0.35, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = pKeys.host,
	})
	onAccent(function(a) keysHost.ScrollBarImageColor3 = a end)
	pad(keysHost, 2, 4, 10, 14)
	list(keysHost, 8)
	local cfgPane = newPane(pCfg.host, "Configs")
	cfgPane.Page.Visible = true
	window.Panes = { Settings = setPane, Configs = cfgPane }

	------------------------------------------------------------------
	-- Settings
	------------------------------------------------------------------
	do
		local ui = setPane:CreateSection("Interface", "Left")
		ui:Dropdown({ Name = "Quality", Options = { "Ultra", "High", "Balanced", "Low" }, Default = Singularity.Quality,
			Flag = "ui_quality", Callback = function(v) Singularity:SetQuality(v) end })
		ui:ColorPicker({ Name = "Accent", Default = Singularity.Accent, Flag = "ui_accent",
			Callback = function(c) Singularity:SetAccent(c) end })
		ui:Toggle({ Name = "Notifications", Default = Singularity.Notifications, Flag = "ui_notify",
			Callback = function(v) Singularity.Notifications = v end })
		ui:Toggle({ Name = "Watermark", Default = cfg.Watermark ~= false, Flag = "ui_watermark",
			Callback = function(v) window:SetWatermark(v) end })

		local audio = setPane:CreateSection("Audio", "Right")
		audio:Toggle({ Name = "Sound effects", Default = Sfx.Enabled, Flag = "ui_sfx",
			Callback = function(v) Sfx.Enabled = v end })
		audio:Slider({ Name = "Volume", Min = 0, Max = 100, Default = math.floor(Sfx.Volume * 100 + 0.5), Suffix = "%", Flag = "ui_volume",
			Callback = function(v) Sfx.Volume = v / 100 end })
		audio:Button({ Name = "Test sound", Callback = function() Sfx:Play("click") end })
		local about = setPane:CreateSection("About", "Left")
		about:Label("Singularity " .. Singularity.Version .. " - event horizon interface")
		about:Divider()
		about:Label("Toggle the interface: " .. keyText(window.ToggleKey))
		about:Label("Overview: the dock icon on the bottom edge")
		about:Label("Bind a key: Keybind Manager, then Start binding")
		about:Label("Cancel a bind pick: Esc")
	end

	------------------------------------------------------------------
	-- Keybind Manager: one row per bind, live-updated
	------------------------------------------------------------------
	local BIND_MODES = { "Toggle", "Hold", "Press" }
	local keysList = new("Frame", {
		Name = "BindList", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, Parent = keysHost,
	})
	list(keysList, 6)

	-- Keybind Manager: a summary, the bind selector, then the live bind list
	local statVals = {}
	local function statCell(parent, key, label, slot)
		local cell = new("Frame", {
			Name = key, BackgroundTransparency = 1, Size = UDim2.new(1 / 3, 0, 1, 0),
			Position = UDim2.fromScale((slot - 1) / 3, 0), Parent = parent,
		})
		statVals[key] = new("TextLabel", {
			Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 26), BackgroundTransparency = 1,
			Text = "0", TextColor3 = Theme.Text, TextSize = 20, FontFace = Fonts.Bold,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = cell,
		})
		new("TextLabel", {
			Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 14), BackgroundTransparency = 1,
			Text = label, TextColor3 = Theme.Soft, TextSize = 11, FontFace = Fonts.Body,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = cell,
		})
	end

	local summary = new("Frame", {
		Name = "Summary", BackgroundColor3 = Theme.Glass, BackgroundTransparency = 0.3,
		Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 1, Parent = keysHost,
	})
	corner(summary, 10)
	stroke(summary, Theme.Line, 1, 0.55)
	statCell(summary, "total", "Binds", 1)
	statCell(summary, "keyed", "Active", 2)
	statCell(summary, "unset", "Unset", 3)

	local selector = new("Frame", {
		Name = "Selector", BackgroundColor3 = Theme.Glass, BackgroundTransparency = 0.3,
		Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 2, Parent = keysHost,
	})
	corner(selector, 10)
	stroke(selector, Theme.Line, 1, 0.55)
	new("TextLabel", {
		Position = UDim2.fromOffset(14, 11), Size = UDim2.new(1, -150, 0, 20), BackgroundTransparency = 1,
		Text = "Bind a feature", TextColor3 = Theme.Text, TextSize = 14, FontFace = Fonts.Semi,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = selector,
	})
	new("TextLabel", {
		Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -150, 0, 16), BackgroundTransparency = 1,
		Text = "Pick a toggle or button in Main, then press a key", TextColor3 = Theme.Soft, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Fonts.Body, Parent = selector,
	})
	local startBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(122, 32),
		BackgroundColor3 = Theme.Accent, AutoButtonColor = false, Text = "Start binding",
		TextColor3 = Theme.Void, TextSize = 12, FontFace = Fonts.Semi, Parent = selector,
	})
	corner(startBtn, 8)
	onAccent(function(a) startBtn.BackgroundColor3 = a end)
	startBtn.MouseEnter:Connect(function() tween(startBtn, EASE.Fast, { BackgroundColor3 = Theme.Hot }) end)
	startBtn.MouseLeave:Connect(function() tween(startBtn, EASE.Fast, { BackgroundColor3 = Theme.Accent }) end)
	startBtn.Activated:Connect(function()
		Sfx:Play("click")
		window:BeginBindPick()
	end)

	keysList.LayoutOrder = 4
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 3,
		Text = "Active binds", TextColor3 = Theme.Soft, TextSize = 11, FontFace = Fonts.Semi,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = keysHost,
	})

	local function bindSource(el)
		if el.Type ~= "Feature" then return "Keybind" end
		local sec = el.Target.Section
		local tabName = sec and sec.Tab and sec.Tab.Name or "Main"
		local secName = sec and sec.Body and sec.Body.Name or ""
		return tabName .. " / " .. secName
	end

	local function refreshBinds()
		for _, c in ipairs(keysList:GetChildren()) do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end
		local keyed = 0
		for _, el in ipairs(Binds) do
			if el.Key then keyed = keyed + 1 end
		end
		statVals.total.Text = tostring(#Binds)
		statVals.keyed.Text = tostring(keyed)
		statVals.unset.Text = tostring(#Binds - keyed)

		if #Binds == 0 then
			new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, TextWrapped = true,
				Text = "Nothing is bound yet. Start binding to put a key on any toggle or button.",
				TextColor3 = Theme.Faint, TextSize = 12, FontFace = Fonts.Body, Parent = keysList,
			})
			return
		end

		for i, el in ipairs(Binds) do
			local isFeature = el.Type == "Feature"
			local isButton = isFeature and el.Target.Type == "Button"
			local row = new("Frame", {
				Name = "Bind" .. i, BackgroundColor3 = Theme.Glass, BackgroundTransparency = 0.3,
				Size = UDim2.new(1, 0, 0, 48), LayoutOrder = i, Parent = keysList,
			})
			corner(row, 8)
			stroke(row, Theme.Line, 1, 0.6)
			new("TextLabel", {
				Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -262, 0, 18), BackgroundTransparency = 1,
				Text = el.Name or "Keybind", TextColor3 = Theme.Text, TextSize = 13, FontFace = Fonts.Semi,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
			})
			new("TextLabel", {
				Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -262, 0, 14), BackgroundTransparency = 1,
				Text = bindSource(el), TextColor3 = Theme.Faint, TextSize = 11, FontFace = Fonts.Body,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
			})
			local chip = new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -172, 0.5, 0), Size = UDim2.fromOffset(64, 22),
				BackgroundColor3 = Theme.Track, Text = keyText(el.Key), TextColor3 = Theme.Frost, TextSize = 11,
				FontFace = Fonts.Mono, Parent = row,
			})
			corner(chip, 6)
			local modeBtn = new("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -76, 0.5, 0), Size = UDim2.fromOffset(88, 22),
				BackgroundColor3 = Theme.Track, Text = isButton and "PRESS" or string.upper(el.Mode or "Toggle"),
				TextColor3 = Theme.Dim, TextSize = 11, FontFace = Fonts.Mono, AutoButtonColor = false, Parent = row,
			})
			corner(modeBtn, 6)
			modeBtn.Activated:Connect(function()
				if isButton then return end
				local idx = table.find(BIND_MODES, el.Mode) or 1
				el:SetMode(BIND_MODES[idx % #BIND_MODES + 1])
				refreshBinds()
			end)
			if isFeature then
				local rm = new("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(56, 22),
					BackgroundColor3 = Theme.Track, Text = "Remove", TextColor3 = Theme.Soft, TextSize = 11,
					FontFace = Fonts.Body, AutoButtonColor = false, Parent = row,
				})
				corner(rm, 6)
				rm.Activated:Connect(function()
					for j, b in ipairs(Binds) do
						if b == el then table.remove(Binds, j) break end
					end
					Sfx:Play("click")
					refreshBinds()
				end)
			end
		end
	end
	window._refreshBinds = refreshBinds
	Singularity._bindsChanged = refreshBinds
	refreshBinds()

	------------------------------------------------------------------
	-- Config Manager
	------------------------------------------------------------------
	local refreshConfigs
	local selected = "default"
	local cfgCurrent = cfgPane:CreateSection("Current config", "Left")
	cfgCurrent:Textbox({ Name = "Name", Placeholder = "default", NoConfig = true,
		Callback = function(t) if t and t ~= "" then selected = t end end })
	cfgCurrent:Button({ Name = "Save", Callback = function()
		local ok, err = Singularity:SaveConfig(selected)
		if ok then Singularity:Notify({ Title = "Saved", Content = selected, Type = "Success" })
		else Singularity:Notify({ Title = "Save failed", Content = tostring(err), Type = "Error" }) end
		refreshConfigs()
	end })
	cfgCurrent:Button({ Name = "Load", Callback = function()
		local ok, err = Singularity:LoadConfig(selected)
		if ok then Singularity:Notify({ Title = "Loaded", Content = selected, Type = "Success" })
		else Singularity:Notify({ Title = "Load failed", Content = tostring(err), Type = "Error" }) end
	end })
	cfgCurrent:Button({ Name = "Delete", Callback = function()
		local ok, err = Singularity:DeleteConfig(selected)
		if ok then Singularity:Notify({ Title = "Deleted", Content = selected, Type = "Warn" })
		else Singularity:Notify({ Title = "Delete failed", Content = tostring(err), Type = "Error" }) end
		refreshConfigs()
	end })
	cfgCurrent:Button({ Name = "Copy setup", Callback = function()
		if type(setclipboard) ~= "function" then
			Singularity:Notify({ Title = "Clipboard unavailable", Type = "Error" }); return
		end
		setclipboard(Singularity:ExportConfig())
		Singularity:Notify({ Title = "Copied", Content = "Setup copied to clipboard.", Type = "Success" })
	end })
	cfgCurrent:Button({ Name = "Paste setup", Callback = function()
		local text = type(getclipboard) == "function" and getclipboard() or nil
		local ok, n = Singularity:ImportConfig(text)
		if ok then Singularity:Notify({ Title = "Imported", Content = n .. " settings applied.", Type = "Success" })
		else Singularity:Notify({ Title = "Import failed", Content = tostring(n), Type = "Error" }) end
	end })

	local cfgSaved = cfgPane:CreateSection("Saved configs", "Right")
	cfgSaved:Label("Stored as JSON in " .. Singularity.Folder .. "/configs. Loading one replaces the current values.")
	local cfgList = new("Frame", {
		Name = "ConfigList", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 100, Parent = cfgSaved.Body,
	})
	list(cfgList, 6)

	refreshConfigs = function()
		for _, c in ipairs(cfgList:GetChildren()) do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end
		local names = Singularity:ListConfigs()
		if #names == 0 then
			new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, TextWrapped = true,
				Text = "No saved configs yet (or file access is unavailable here).",
				TextColor3 = Theme.Faint, TextSize = 12, FontFace = Fonts.Body, Parent = cfgList,
			})
			return
		end
		for i, name in ipairs(names) do
			local btn = new("TextButton", {
				Name = name, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Track, AutoButtonColor = false,
				Text = name, TextColor3 = selected == name and Theme.Frost or Theme.Text, TextSize = 13,
				FontFace = Fonts.Body, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = i, Parent = cfgList,
			})
			corner(btn, 6)
			pad(btn, 12, 0, 12, 0)
			btn.Activated:Connect(function()
				selected = name
				refreshConfigs()
			end)
		end
	end
	window._refreshConfigs = refreshConfigs
	refreshConfigs()


	local function watchWidth(p, panes)
		local function check()
			local single = p.host.AbsoluteSize.X < 540
			for _, pane in ipairs(panes) do pane:_reflow(single) end
		end
		p.host:GetPropertyChangedSignal("AbsoluteSize"):Connect(check)
		check()
	end
	watchWidth(pSet, { setPane })
	watchWidth(pCfg, { cfgPane })
	window._mainPanes = {}
	watchWidth(pMain, window._mainPanes)
	-- Main panes are added as tabs are created, so keep the list live
	pMain.host:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local single = pMain.host.AbsoluteSize.X < 540
		for _, t in ipairs(window.Tabs) do t:_reflow(single) end
	end)

	------------------------------------------------------------------
	-- section bar, pinned to the top of the screen
	------------------------------------------------------------------
	local labels = compact and SECTION_SHORT or SECTION_NAMES
	local widths, barW = {}, 12
	for i, l in ipairs(labels) do
		widths[i] = math.floor(30 + #l * 7.6)
		barW = barW + widths[i]
	end
	local BAR_HIDDEN = -(BAR_H + EDGE + 8)
	local barShell = new("Frame", {
		Name = "SectionBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, BAR_HIDDEN),
		Size = UDim2.fromOffset(barW, BAR_H), BackgroundTransparency = 1, ZIndex = 10, Parent = gui,
	})
	local barScale = new("UIScale", { Parent = barShell })
	local barSlab = new("Frame", {
		Name = "Slab", Position = UDim2.fromOffset(0, 3), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(3, 4, 8),
		BackgroundTransparency = 0.3, ZIndex = 1, Parent = barShell,
	})
	corner(barSlab, 22)
	local bar = FX.Glass(barShell, 22, { Name = "Bar", Transparency = 0.1, ZIndex = 2 })
	FX.RimStroke(bar, 1.2, 12, 0.2, function() return window.Visible end)
	local lens = new("Frame", {
		Name = "Lens", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.new(0, widths[1], 1, -10),
		BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.74, ZIndex = 3, Parent = bar,
	})
	corner(lens, 0, 1)
	local lensStroke = stroke(lens, Theme.Hot, 1, 0.5)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.5) }),
		Parent = lens,
	})
	onAccent(function(a, h) lens.BackgroundColor3 = a lensStroke.Color = h end)

	local barLabels, offsets = {}, {}
	do
		local x = 6
		for i, l in ipairs(labels) do
			offsets[i] = x
			local b = new("TextButton", {
				Name = SECTION_NAMES[i], Position = UDim2.new(0, x, 0, 0), Size = UDim2.new(0, widths[i], 1, 0), FontFace = Fonts.Semi,
				TextSize = compact and 11 or 12, Text = l, TextColor3 = i == 1 and Theme.Text or Theme.Dim, ZIndex = 4, Parent = bar,
			})
			barLabels[i] = b
			b.MouseEnter:Connect(function()
				if window.Section ~= i then tween(b, EASE.Fast, { TextColor3 = Theme.Text }) end
			end)
			b.MouseLeave:Connect(function()
				if window.Section ~= i then tween(b, EASE.Med, { TextColor3 = Theme.Dim }) end
			end)
			b.Activated:Connect(function()
				local m = FX.Mouse()
				FX.Ripple(bar, 22, Theme.Hot, m.X, m.Y)
				window:SetSection(i)
			end)
			x = x + widths[i]
		end
	end

	------------------------------------------------------------------
	-- window controls, top right corner of the screen
	------------------------------------------------------------------
	local ctrl = new("Frame", {
		Name = "Controls", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -EDGE, 0, BAR_HIDDEN),
		Size = UDim2.fromOffset(compact and 70 or 80, BAR_H), BackgroundTransparency = 1, ZIndex = 10, Parent = gui,
	})
	local ctrlScale = new("UIScale", { Parent = ctrl })
	list(ctrl, 8, {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local function ctrlButton(order, build)
		local sz = compact and 30 or 34
		local b = new("TextButton", { Size = UDim2.fromOffset(sz, sz), BackgroundTransparency = 1, LayoutOrder = order, Parent = ctrl })
		local face = FX.Glass(b, "circle", { Transparency = 0.1, ZIndex = 1 })
		local fs = stroke(face, Theme.Line, 1, 0.3)
		local us = new("UIScale", { Parent = face })
		local sp = FX.ScaleSpring(us, 20, 0.6)
		local parts = build(face)
		b.MouseEnter:Connect(function() sp:Goal(1.12) tween(fs, EASE.Fast, { Color = Theme.Frost, Transparency = 0 }) end)
		b.MouseLeave:Connect(function() sp:Goal(1) tween(fs, EASE.Med, { Color = Theme.Line, Transparency = 0.3 }) end)
		b.MouseButton1Down:Connect(function() sp:Goal(0.88) end)
		b.MouseButton1Up:Connect(function() sp:Goal(1.12) end)
		return b, parts, face
	end
	local minBtn = ctrlButton(1, function(face)
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 1.6),
			BackgroundColor3 = Theme.Soft, ZIndex = 3, Parent = face,
		})
	end)
	local closeBtn, closeParts = ctrlButton(2, function(face)
		local arms = {}
		for _, rot in ipairs({ 45, -45 }) do
			arms[#arms + 1] = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(13, 1.6),
				Rotation = rot, BackgroundColor3 = Theme.Soft, ZIndex = 3, Parent = face,
			})
		end
		return arms
	end)

	------------------------------------------------------------------
	-- resize grip
	------------------------------------------------------------------
	local grip = new("TextButton", {
		Name = "Grip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -7, 1, -7), Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1, ZIndex = 60, Parent = stage,
	})
	local gripBars = {}
	for i = 1, 3 do
		gripBars[i] = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -13 + (i - 1) * 4.2, 1, -13 + (i - 1) * 4.2),
			Size = UDim2.fromOffset(18 - (i - 1) * 6, 1.6), Rotation = -45, BackgroundColor3 = Theme.Faint, ZIndex = 61, Parent = grip,
		})
		corner(gripBars[i], 0, 0.5)
	end
	grip.MouseEnter:Connect(function()
		for _, b in ipairs(gripBars) do tween(b, EASE.Fast, { BackgroundColor3 = Theme.Accent }) end
	end)
	grip.MouseLeave:Connect(function()
		for _, b in ipairs(gripBars) do tween(b, EASE.Med, { BackgroundColor3 = Theme.Faint }) end
	end)
	local rs0, rp0
	trackDrag(grip, {
		Begin = function()
			rs0, rp0 = window.Size, root.Position
		end,
		Move = function(_, d)
			local s = rootScale.Scale
			local nw, nh = fit(rs0.X + d.X / s, rs0.Y + d.Y / s)
			window.Size = Vector2.new(nw, nh)
			root.Size = UDim2.fromOffset(nw, nh)
			-- keep the top-left corner pinned while the window grows
			root.Position = UDim2.new(rp0.X.Scale, rp0.X.Offset + (nw - rs0.X) * s / 2, rp0.Y.Scale, rp0.Y.Offset + (nh - rs0.Y) * s / 2)
		end,
	})
	function window:SetSize(w, h)
		w, h = fit(w, h)
		window.Size = Vector2.new(w, h)
		root.Size = UDim2.fromOffset(w, h)
	end
	function window:SetScale(s)
		userScale = math.clamp(s, 0.6, 1.5)
		rootScale.Scale = userScale
		barScale.Scale, ctrlScale.Scale = userScale, userScale
		if window._railScale then window._railScale.Scale = userScale end
	end

	------------------------------------------------------------------
	-- tab rail, on the far right edge of the screen (Main only)
	------------------------------------------------------------------
	local rail = new("Frame", {
		Name = "Rail", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -EDGE, 0.5, (TOP - EDGE) / 2),
		Size = UDim2.fromOffset(BTN, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 10, Parent = gui,
	})
	local railScale = new("UIScale", { Parent = rail })
	window._railScale = railScale
	list(rail, compact and 8 or 12, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local railShown = false

	local function setRail(show)
		railShown = show
		local n = #window.Tabs
		for i, tab in ipairs(window.Tabs) do
			local delay = (show and (i - 1) or (n - i)) * 0.045
			local info = show
				and TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, delay)
				or TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In, 0, false, delay)
			tab.Shown = show
			if not show then tab.Hover = false end
			tween(tab.Shell, info, { Position = show and UDim2.new() or UDim2.fromOffset(RAIL_OUT, 0) })
			applyPill(tab, info)
			tab.Hit.Visible = show
		end
	end

	------------------------------------------------------------------
	-- sections: panels slide horizontally. The arriving panel enters from
	-- off screen on one side while the leaving panel slides fully off screen
	-- on the other. Both use the same curve and the same distance, so the
	-- motion is one smooth movement with no stops.
	------------------------------------------------------------------
	local OV = { on = false, tok = 0 } -- overview state (see the overview block below)
	local SWITCH = TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)
	local SINK_SCALE = 0.86   -- leaving panel shrinks to this, for depth
	local SINK_DROP = 28      -- and sinks this many px as it goes back
	local ARRIVE_SCALE = 0.9  -- arriving panel starts this small and grows into place
	local TURN_IN, TURN_AWAY = 0.64, 0.6 -- fake 3D: panel widths mid-turn (fraction of full width)

	local flipTok = 0
	local function flip(out, inc, dir)
		flipTok = flipTok + 1
		OV.tok = OV.tok + 1 -- cancels any overview cleanup still pending
		local tok = flipTok
		local W = window.Size.X

		-- distance (in panel units) that carries a panel fully past the screen edge
		local g = guiSize(gui)
		local s = math.max(rootScale.Scale * popScale.Scale, 0.01)
		local travel = g.X / (2 * s) + W / 2 + 80 / s

		-- every panel that is not part of this switch rests hidden
		for _, p in pairs(panels) do
			if p ~= out and p ~= inc then
				snap(p.holder, { Visible = false, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 1 })
				snap(p.scale, { Scale = 1 })
				snap(p.veil, { BackgroundTransparency = 1 })
			end
		end

		-- fake 3D turn: the leaving panel swings away from the viewer (narrows, darkens,
		-- sinks back); the arriving panel starts narrow and in shadow and swings flat
		local inW = Singularity.ReducedMotion and 1 or TURN_IN
		local outW = Singularity.ReducedMotion and 1 or TURN_AWAY

		-- arriving panel: fully off screen, a little small, narrowed, on top
		snap(inc.holder, { Visible = true, Position = UDim2.new(0.5, dir * travel, 0.5, 0), Size = UDim2.fromScale(inW, 1), ZIndex = 2 })
		snap(inc.scale, { Scale = ARRIVE_SCALE })
		snap(inc.veil, { BackgroundTransparency = 0.5 })

		-- leaving panel: behind, starts where it is
		snap(out.holder, { Visible = true, ZIndex = 1 })
		snap(out.veil, { BackgroundTransparency = 1 })

		-- same curve, same time: one turns away and sinks, the other turns in
		tween(out.holder, SWITCH, { Position = UDim2.new(0.5, -dir * travel, 0.5, SINK_DROP), Size = UDim2.fromScale(outW, 1) })
		tween(out.scale, SWITCH, { Scale = SINK_SCALE })
		tween(out.veil, SWITCH, { BackgroundTransparency = 0.5 })

		tween(inc.holder, SWITCH, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) })
		tween(inc.scale, SWITCH, { Scale = 1 })
		tween(inc.veil, SWITCH, { BackgroundTransparency = 1 })

		task.delay(SWITCH.Time + 0.02, function()
			if tok ~= flipTok then return end
			-- the leaving panel is already fully off screen, so hiding it is not visible
			snap(out.holder, { Visible = false, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 1 })
			snap(out.scale, { Scale = 1 })
			snap(out.veil, { BackgroundTransparency = 1 })
			snap(inc.holder, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 1 })
			snap(inc.scale, { Scale = 1 })
		end)

	end

	local LENS_MOVE = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local function moveLens(i)
		tween(lens, LENS_MOVE, { Position = UDim2.new(0, offsets[i], 0.5, 0), Size = UDim2.new(0, widths[i], 1, -10) })
		for k, b in ipairs(barLabels) do tween(b, EASE.Med, { TextColor3 = k == i and Theme.Text or Theme.Dim }) end
	end

	------------------------------------------------------------------
	-- overview: zoom out so all four panels sit side by side, then click
	-- one to zoom back in on that section
	------------------------------------------------------------------
	local OV_IN = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	local OV_GAP = compact and 14 or 26
	local OV_TURN = 0.8 -- panels out of focus are narrowed, like a carousel turning away
	local ovRoot = root.Position

	-- scale for the four panels side by side, and each panel's x offset
	local function ovLayout()
		local g = guiSize(gui)
		local s = math.max(rootScale.Scale * popScale.Scale, 0.01)
		local W, H = window.Size.X, window.Size.Y
		local k = math.min((g.X * 0.94 - 3 * OV_GAP) / (4 * W * s), (g.Y * 0.6) / (H * s), 0.5)
		k = math.max(k, 0.2)
		local xs = {}
		for i = 1, 4 do xs[i] = (i - 2.5) * (W * k + OV_GAP / s) end
		return k, xs
	end

	local function ovEnter()
		OV.on = true
		OV.tok = OV.tok + 1
		ovRoot = root.Position
		local k, xs = ovLayout()
		setRail(false)
		for i, p in ipairs(panels) do
			local active = i == window.Section
			p.holder.ZIndex = active and 2 or 1
			p.hit.Visible = true
			p.holder.Visible = true
			if not active then
				snap(p.scale, { Scale = k * 0.7 })
				snap(p.veil, { BackgroundTransparency = 1 })
			end
			tween(p.holder, OV_IN, { Position = UDim2.new(0.5, xs[i], 0.5, 0), Size = UDim2.fromScale(active and 1 or OV_TURN, 1) })
			tween(p.scale, OV_IN, { Scale = k })
			tween(p.veil, OV_IN, { BackgroundTransparency = active and 1 or 0.55 })
		end
		tween(root, OV_IN, { Position = UDim2.new(0.5, 0, 0.5, 0) })
	end

	-- idx: the section to zoom into (the current one when cancelling)
	local function ovExit(idx)
		OV.on = false
		OV.tok = OV.tok + 1
		local tok = OV.tok
		if idx ~= window.Section then
			window.Section = idx
			Sfx:Play("tab")
			moveLens(idx)
			if idx == 3 and window._refreshBinds then window._refreshBinds() end
			if idx == 4 and window._refreshConfigs then window._refreshConfigs() end
		end
		setRail(idx == 1)
		for i, p in ipairs(panels) do
			local chosen = i == idx
			p.hit.Visible = false
			p.holder.ZIndex = chosen and 2 or 1
			-- everything zooms toward the centre; the chosen panel grows to full size
			tween(p.holder, OV_IN, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) })
			tween(p.scale, OV_IN, { Scale = chosen and 1 or 0.7 })
			tween(p.veil, OV_IN, { BackgroundTransparency = 1 })
		end
		tween(root, OV_IN, { Position = ovRoot })
		task.delay(OV_IN.Time + 0.02, function()
			if tok ~= OV.tok then return end
			for i, p in ipairs(panels) do
				snap(p.holder, { Visible = i == idx, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 1 })
				snap(p.scale, { Scale = 1 })
				snap(p.veil, { BackgroundTransparency = 1 })
			end
		end)
	end

	function window:ShowOverview(on)
		if on == OV.on then return end
		if on then ovEnter() else ovExit(self.Section) end
		for _, sq in ipairs(window._dockSquares or {}) do
			tween(sq, EASE.Med, { BackgroundColor3 = OV.on and Theme.Hot or Theme.Soft })
		end
	end

	function window:ToggleOverview()
		self:ShowOverview(not OV.on)
	end

	-- one transparent button over each panel, only live in overview
	for _, p in ipairs(panels) do
		local hit = new("TextButton", {
			Name = "OverviewHit", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
			ZIndex = 60, Visible = false, Parent = p.holder,
		})
		p.hit = hit
		hit.MouseEnter:Connect(function()
			if OV.on and p.idx ~= window.Section then tween(p.veil, EASE.Fast, { BackgroundTransparency = 0.8 }) end
		end)
		hit.MouseLeave:Connect(function()
			if OV.on and p.idx ~= window.Section then tween(p.veil, EASE.Med, { BackgroundTransparency = 0.55 }) end
		end)
		hit.Activated:Connect(function() ovExit(p.idx) end)
	end

	------------------------------------------------------------------
	-- bind picker: Keybind Manager -> Main (click a feature) -> press a key -> back
	------------------------------------------------------------------
	local pick = { stage = nil, hits = {}, conn = nil }
	local function clearPickHits()
		for _, h in ipairs(pick.hits) do
			if h.Parent then h:Destroy() end
		end
		table.clear(pick.hits)
	end
	local function endPick()
		pick.stage = nil
		clearPickHits()
		if pick.conn then pick.conn:Disconnect(); pick.conn = nil end
		Listening = false
		local tab = window.ActiveTab
		swapText(pMain.subtitle, tab and (tab.Subtitle or "") or "")
	end
	local function finishBind(el, key)
		-- a feature holds one key, and a key drives one feature: the old owner lets go
		for j = #Binds, 1, -1 do
			local b = Binds[j]
			if b.Type == "Feature" and (b.Target == el or b.Key == key) then
				table.remove(Binds, j)
			end
		end
		Binds[#Binds + 1] = newFeatureBind(el, key, el.Type == "Button" and "Press" or "Toggle")
		endPick()
		Sfx:Play("toggle_on")
		Singularity:Notify({ Title = "Bound", Content = keyText(key) .. " to " .. (el.Name or "feature"), Type = "Success" })
		if window._refreshBinds then window._refreshBinds() end
		window:SetSection(3)
	end

	function window:BeginBindPick()
		if pick.stage then return end
		pick.stage = "feature"
		self:SetSection(1)
		swapText(pMain.subtitle, "Click a feature to bind  -  Esc cancels")
		for _, el in ipairs(Features) do
			local row, tab = el._row, el.Section and el.Section.Tab
			if row and tab and tab.Window == self then
				local hit = new("TextButton", {
					Name = "BindPick", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Accent,
					BackgroundTransparency = 0.88, AutoButtonColor = false, Text = "", ZIndex = 20, Parent = row,
				})
				corner(hit, 6)
				stroke(hit, Theme.Accent, 1, 0.4)
				new("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(44, 14),
					BackgroundTransparency = 1, Text = "BIND", TextColor3 = Theme.Accent, TextSize = 9,
					FontFace = Fonts.Mono, ZIndex = 21, Parent = hit,
				})
				hit.MouseEnter:Connect(function() tween(hit, EASE.Fast, { BackgroundTransparency = 0.72 }) end)
				hit.MouseLeave:Connect(function() tween(hit, EASE.Med, { BackgroundTransparency = 0.88 }) end)
				hit.Activated:Connect(function() self:_chooseFeature(el) end)
				pick.hits[#pick.hits + 1] = hit
			end
		end
		if pick.conn then pick.conn:Disconnect() end
		pick.conn = UserInputService.InputBegan:Connect(function(input, gp)
			if not gp and input.KeyCode == Enum.KeyCode.Escape then self:CancelBindPick() end
		end)
	end

	function window:_chooseFeature(el)
		if pick.stage ~= "feature" then return end
		pick.stage = "key"
		clearPickHits()
		if pick.conn then pick.conn:Disconnect() end
		Sfx:Play("click")
		swapText(pMain.subtitle, "Press a key for " .. (el.Name or "this feature") .. "  -  Esc cancels")
		Listening = true
		pick.conn = UserInputService.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.Keyboard then
				if input.KeyCode == Enum.KeyCode.Escape then
					self:CancelBindPick()
				else
					finishBind(el, input.KeyCode)
				end
			elseif t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
				finishBind(el, t)
			end
		end)
	end

	function window:CancelBindPick()
		if not pick.stage then return end
		endPick()
		Sfx:Play("tab")
		self:SetSection(3)
	end

	function window:SetSection(which)
		local idx = type(which) == "number" and which or table.find(SECTION_NAMES, which) or table.find(SECTION_SHORT, which)
		if not idx or not panels[idx] then return end
		if pick.stage == "feature" and idx ~= 1 then endPick() end
		if OV.on then return ovExit(idx) end
		if idx == self.Section then return end
		local outgoing, incoming = panels[self.Section], panels[idx]
		local dir = idx > self.Section and 1 or -1
		Sfx:Play("tab")
		self.Section = idx
		flip(outgoing, incoming, dir)
		moveLens(idx)
		setRail(idx == 1)
		if idx == 3 and self._refreshBinds then self._refreshBinds() end
		if idx == 4 and self._refreshConfigs then self._refreshConfigs() end
	end

	------------------------------------------------------------------
	-- watermark: a small rgb pill in the bottom-left corner that shows the hub name
	local wmGui = makeGui("SingularityWatermark", 600, true)
	local wmCustom = cfg.WatermarkText ~= nil
	local wmLabel = new("TextLabel", {
		Name = "Watermark", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, EDGE, 1, -EDGE),
		Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(8, 10, 16), BackgroundTransparency = 0.15,
		FontFace = Fonts.Bold, TextSize = 13, Text = cfg.WatermarkText or window.Title, TextColor3 = Color3.new(1, 1, 1),
		Visible = false, ZIndex = 5, Parent = wmGui,
	})
	corner(wmLabel, 13)
	pad(wmLabel, 14, 0, 14, 0)
	local wmStroke = stroke(wmLabel, Color3.new(1, 1, 1), 1.5, 0.1)
	local wmSweep = new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 90)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(60, 255, 140)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 150, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 90)),
		}),
		Parent = wmStroke,
	})
	local wmOn = false
	local function setWatermark(on)
		wmOn = on and true or false
		wmLabel.Visible = wmOn
	end
	setWatermark(cfg.Watermark ~= false)
	function window:SetWatermark(on) setWatermark(on) end
	function window:SetWatermarkText(text)
		wmCustom = true
		wmLabel.Text = tostring(text or "")
	end
	FX.Ticker(function(dt, t)
		if wmGui.Parent == nil then return false end
		if not wmOn then return true end
		local hue = (t * 0.1) % 1
		wmLabel.TextColor3 = Color3.fromHSV(hue, 0.5, 1)
		wmStroke.Color = Color3.fromHSV((hue + 0.5) % 1, 0.75, 1)
		wmSweep.Rotation = (t * 120) % 360
		return true
	end)

	-- the hub name: header and watermark follow it unless a watermark text was given
	function window:SetTitle(text)
		self.Title = tostring(text or "Singularity")
		if not self.ActiveTab then pMain.title.Text = self.Title end
		if not wmCustom then wmLabel.Text = self.Title end
	end

	------------------------------------------------------------------
	-- open / close
	------------------------------------------------------------------
	local orb = new("Frame", {
		Name = "Orb", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 46, 0.5, 0), Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1, Parent = gui,
	})
	local orbScale = new("UIScale", { Scale = 0, Parent = orb })
	local orbFace = FX.Glass(orb, "circle", { Transparency = 0.08, ZIndex = 1 })
	local orbRim = stroke(orbFace, Theme.Accent, 1.4, 0.1)
	local sigilHolder, sigil = Geo.Sigil(orbFace, 52, Theme.Hot)
	local orbImage = new("ImageLabel", {
		Name = "ToggleIcon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 2, Parent = orbFace,
	})
	-- a custom icon replaces the sigil. Accepts an asset id string, a number, or "" for the sigil.
	local function applyToggleIcon(image)
		local id = image
		if type(id) == "number" then id = tostring(id) end
		if type(id) == "string" and string.match(id, "^%d+$") then id = "rbxassetid://" .. id end
		if type(id) == "string" and id ~= "" then
			orbImage.Image = id
			orbImage.Visible = true
			sigilHolder.Visible = false
		else
			orbImage.Visible = false
			sigilHolder.Visible = true
		end
	end
	applyToggleIcon(cfg.ToggleIcon)
	function window:SetToggleIcon(image) applyToggleIcon(image) end
	onAccent(function(a, h)
		orbRim.Color = a
		for _, part in ipairs(sigil) do part.BackgroundColor3 = h end
	end)
	local orbHit = new("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = orb })
	local function limitsOrb()
		local g = guiSize(gui)
		return g, 28, 28, g.X - 28, g.Y - 28
	end
	makeDraggable(orbHit, orb, limitsOrb, function() window:Toggle() end)

	------------------------------------------------------------------
	-- overview dock: floating icon on the bottom edge of the screen
	------------------------------------------------------------------
	local DOCK = compact and 40 or 46
	local DOCK_SHOWN = UDim2.new(0.5, 0, 1, -EDGE)
	local DOCK_HIDDEN = UDim2.new(0.5, 0, 1, DOCK + EDGE + 20)
	local dockShell = new("Frame", {
		Name = "OverviewDock", AnchorPoint = Vector2.new(0.5, 1), Position = DOCK_HIDDEN,
		Size = UDim2.fromOffset(DOCK, DOCK), BackgroundTransparency = 1, ZIndex = 10, Parent = gui,
	})
	local dockBtn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 4, Parent = dockShell })
	local dockFace = FX.Glass(dockShell, "circle", { Transparency = 0.1, ZIndex = 1 })
	local dockStroke = stroke(dockFace, Theme.Line, 1, 0.3)
	local dockScale = new("UIScale", { Parent = dockFace })
	local dockSpring = FX.ScaleSpring(dockScale, 20, 0.6)
	-- four small squares: the overview icon
	local dockSquares = {}
	window._dockSquares = dockSquares
	for n = 0, 3 do
		local col, row = n % 2, math.floor(n / 2)
		local sq = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, col == 0 and -5 or 5, 0.5, row == 0 and -5 or 5),
			Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Theme.Soft, ZIndex = 3, Parent = dockFace,
		})
		corner(sq, 2)
		dockSquares[#dockSquares + 1] = sq
	end
	dockBtn.MouseEnter:Connect(function()
		dockSpring:Goal(1.12)
		tween(dockStroke, EASE.Fast, { Color = Theme.Frost, Transparency = 0 })
	end)
	dockBtn.MouseLeave:Connect(function()
		dockSpring:Goal(1)
		tween(dockStroke, EASE.Med, { Color = Theme.Line, Transparency = 0.3 })
	end)
	dockBtn.MouseButton1Down:Connect(function() dockSpring:Goal(0.88) end)
	dockBtn.MouseButton1Up:Connect(function() dockSpring:Goal(1.12) end)
	dockBtn.Activated:Connect(function() window:ToggleOverview() end)

	local savedPos = root.Position
	local openTok = 0
	function window:Open()
		if self.Visible then return end
		self.Visible = true
		openTok = openTok + 1
		Sfx:Play("open")
		if not root.Visible then
			root.Visible = true
			root.Position = savedPos
			snapAll(false)
		end
		panels[self.Section].holder.Visible = true
		tween(orbScale, EASE.Fast, { Scale = 0 })
		setShown(true, EASE.Rise, OPEN_POP)
		tween(barShell, EASE.Rise, { Position = UDim2.new(0.5, 0, 0, EDGE) })
		tween(ctrl, EASE.Rise, { Position = UDim2.new(1, -EDGE, 0, EDGE) })
		tween(dockShell, EASE.Rise, { Position = DOCK_SHOWN })
		setRail(self.Section == 1)
		showBackdrop(true, ti(0.6, Enum.EasingStyle.Quad))
	end
	function window:Close()
		if not self.Visible then return end
		if OV.on then self:ShowOverview(false) end
		self.Visible = false
		openTok = openTok + 1
		local tok = openTok
		Sfx:Play("close")
		savedPos = root.Position
		setShown(false, EASE.Leave, EASE.Leave)
		tween(barShell, EASE.Leave, { Position = UDim2.new(0.5, 0, 0, BAR_HIDDEN) })
		tween(ctrl, EASE.Leave, { Position = UDim2.new(1, -EDGE, 0, BAR_HIDDEN) })
		tween(dockShell, EASE.Leave, { Position = DOCK_HIDDEN })
		setRail(false)
		showBackdrop(false, ti(0.35, Enum.EasingStyle.Quad))
		task.delay(0.34, function()
			if openTok ~= tok then return end
			root.Visible = false
			tween(orbScale, EASE.Pop, { Scale = 1 })
		end)
		if not self._announced then
			self._announced = true
			Singularity:Notify({
				Title = "Interface collapsed",
				Content = "Tap the orb or press " .. keyText(self.ToggleKey) .. " to open it again.",
				Duration = 4,
			})
		end
	end
	function window:Toggle()
		if self.Visible then self:Close() else self:Open() end
	end

	minBtn.Activated:Connect(function() window:Close() end)
	local closeArmed = false
	closeBtn.Activated:Connect(function()
		if closeArmed then
			Singularity:Unload()
			return
		end
		closeArmed = true
		for _, a in ipairs(closeParts) do tween(a, EASE.Fast, { BackgroundColor3 = NotifyColors.Error }) end
		Singularity:Notify({ Title = "Unload interface?", Content = "Press the close button again to unload.", Type = "Warn", Duration = 2.5 })
		task.delay(2.5, function()
			closeArmed = false
			for _, a in ipairs(closeParts) do tween(a, EASE.Fast, { BackgroundColor3 = Theme.Soft }) end
		end)
	end)

	connect(UserInputService.InputBegan, function(input, gp)
		if gp or Listening then return end
		if window.ToggleKey and input.KeyCode == window.ToggleKey then window:Toggle() end
	end)

	------------------------------------------------------------------
	-- tabs: rail buttons on the right, pages inside the Main section
	------------------------------------------------------------------
	local mainHost = pMain.host
	local PAGE_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local PAGE_IN = TweenInfo.new(0.46, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local PAGE_TURN = 0.9 -- pages narrow slightly as they turn
	local swapToken = 0

	function window:SelectTab(tab)
		if self.ActiveTab == tab then return end
		local prev = self.ActiveTab
		self.ActiveTab = tab
		swapText(pMain.title, tab.Name)
		swapText(pMain.subtitle, tab.Subtitle or "")
		if prev then
			prev.Active = false
			applyPill(prev, EASE.Fast)
		end
		tab.Active = true
		applyPill(tab, EASE.Fast)
		if not prev then
			tab.Page.Visible = true
			return
		end
		Sfx:Play("tab")
		swapToken = swapToken + 1
		local tok = swapToken
		local dir = tab.Index > prev.Index and 1 or -1
		for _, t in ipairs(self.Tabs) do
			if t ~= prev and t ~= tab then
				t.Page.Visible = false
				t.Veil.BackgroundTransparency = 1
			end
		end
		prev.Page.ZIndex, prev.Veil.ZIndex = 1, 2
		tab.Page.ZIndex, tab.Veil.ZIndex = 3, 4
		-- the old page slides off and dims, then the new one rises in
		local out = tween(prev.Veil, PAGE_OUT, { BackgroundTransparency = 0.04 })
		tween(prev.Page, PAGE_OUT, { Position = UDim2.new(0.5, 0, 0.5, -16 * dir), Size = UDim2.fromScale(PAGE_TURN, 1) })
		tween(prev.Scale, PAGE_OUT, { Scale = 0.97 })
		out.Completed:Connect(function(state)
			if state ~= Enum.PlaybackState.Completed or tok ~= swapToken then return end
			prev.Page.Visible = false
			prev.Page.Size = UDim2.fromScale(1, 1)
			tab.Page.Position = UDim2.new(0.5, 0, 0.5, 22 * dir)
			tab.Page.Size = UDim2.fromScale(PAGE_TURN, 1)
			tab.Scale.Scale = 0.97
			tab.Veil.BackgroundTransparency = 0.04
			tab.Page.Visible = true
			tween(tab.Page, PAGE_IN, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) })
			tween(tab.Scale, PAGE_IN, { Scale = 1 })
			tween(tab.Veil, PAGE_IN, { BackgroundTransparency = 1 })
		end)
	end

	function window:CreateTab(name, opts)
		local idx = #self.Tabs + 1
		local page, left, right = makePage(mainHost, name)
		page.AnchorPoint = Vector2.new(0.5, 0.5)
		page.Position = UDim2.fromScale(0.5, 0.5)
		local pscale = new("UIScale", { Parent = page })
		local pveil = new("Frame", {
			Name = "Veil", BackgroundColor3 = Theme.Panel, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = mainHost,
		})
		corner(pveil, 10)
		local tab = setmetatable({
			Name = name, Index = idx, Window = self, Page = page, Left = left, Right = right, Scale = pscale, Veil = pveil,
			_colOrder = {}, _sections = {}, _single = false, Shown = false, Active = false, Hover = false,
			Subtitle = type(opts) == "table" and opts.Description or nil,
		}, Tab)
		tab:_reflow(mainHost.AbsoluteSize.X < 540)

		local iconName = (type(opts) == "table" and opts.Icon) or (type(opts) == "string" and opts)
			or TAB_ICONS[string.lower(name)] or DEFAULT_TAB_ICON

		local radius = math.floor(BTN * 0.34)
		local slot = new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(BTN, BTN + 4), LayoutOrder = idx, Parent = rail })
		local shell = new("Frame", {
			Name = "Shell", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(RAIL_OUT, 0), Parent = slot,
		})
		local pill = new("Frame", {
			Name = "Pill", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, BTN / 2),
			Size = UDim2.fromOffset(BTN, BTN), Parent = shell,
		})
		local fscale = new("UIScale", { Parent = pill })
		local slabP = new("Frame", {
			Name = "Slab", Position = UDim2.fromOffset(0, 3), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(3, 4, 8),
			BackgroundTransparency = 1, Parent = pill,
		})
		corner(slabP, radius)
		local face = new("Frame", {
			Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Glass, BackgroundTransparency = 1, ZIndex = 2, Parent = pill,
		})
		corner(face, radius)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(176, 180, 198)), Parent = face })
		local rimP = stroke(face, Theme.Line, 1.3, 1)
		local halo = new("Frame", {
			Name = "Halo", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, ZIndex = 2, Parent = face,
		})
		corner(halo, radius)
		local glyph = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(BTN * 0.46, BTN * 0.46),
			FontFace = Fonts.Heavy, TextSize = 11, Text = string.upper(string.sub(name, 1, 1)), TextColor3 = Theme.Soft,
			TextTransparency = 1, ZIndex = 3, Parent = face,
		})
		corner(glyph, 0, 1)
		local glyphRing = stroke(glyph, Theme.Soft, 1.2, 1)
		local icon = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(BTN * 0.5, BTN * 0.5),
			BackgroundTransparency = 1, ImageColor3 = Theme.Soft, ImageTransparency = 1, Visible = false, ZIndex = 3, Parent = face,
		})
		Icons:Bind(icon, iconName, function(ok)
			if ok then
				icon.Visible = true
				glyph.Visible = false
			end
		end)
		-- the marker on the window side of the rail shows the open tab
		local pip = new("Frame", {
			Name = "Pip", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -5, 0, BTN / 2), Size = UDim2.fromOffset(3, 0),
			BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, Parent = shell,
		})
		corner(pip, 0, 0.5)
		local hit = new("TextButton", { Name = "Hit", Size = UDim2.fromScale(1, 1), ZIndex = 8, Visible = false, Parent = slot })

		-- name tag that slides out to the left on hover
		local tip = FX.Glass(shell, 10, {
			Name = "Tip", Transparency = 1, ZIndex = 9, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -4, 0, BTN / 2),
			Size = UDim2.fromOffset(0, 26),
		})
		tip.AutomaticSize = Enum.AutomaticSize.X
		local tipStroke = stroke(tip, Theme.Line, 1, 1)
		local tipText = new("TextLabel", {
			Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, FontFace = Fonts.Semi, TextSize = 12, Text = name,
			TextTransparency = 1, ZIndex = 10, Parent = tip,
		})
		pad(tipText, 10, 0, 10, 0)
		local function showTip(on)
			local info = on and EASE.Med or EASE.Fast
			tween(tip, info, { BackgroundTransparency = on and 0.08 or 1, Position = UDim2.new(0, on and -12 or -4, 0, BTN / 2) })
			tween(tipText, info, { TextTransparency = on and 0 or 1 })
			tween(tipStroke, info, { Transparency = on and 0.25 or 1 })
		end

		tab.Face, tab.Slab, tab.Rim, tab.Icon, tab.Glyph, tab.GlyphRing, tab.Pip, tab.Halo = face, slabP, rimP, icon, glyph, glyphRing, pip, halo
		tab.Shell, tab.Hit, tab.Slot = shell, hit, slot

		-- springs: hover scale and the magnetic pull toward the cursor
		local b = {}
		local mx, my = 0, 0
		local function place() pill.Position = UDim2.new(0.5, mx, 0, BTN / 2 + my) end
		b.mx = FX.Spring(0, 16, 0.7, function(x) mx = x place() end)
		b.my = FX.Spring(0, 16, 0.7, function(x) my = x place() end)
		b.sc = FX.ScaleSpring(fscale, 20, 0.58)

		local hovered = false
		hit.MouseEnter:Connect(function()
			hovered = true
			tab.Hover = true
			applyPill(tab, EASE.Fast)
			b.sc:Goal(1.12)
			showTip(true)
			FX.Ticker(function()
				if not hovered or not slot.Parent then
					b.mx:Goal(0)
					b.my:Goal(0)
					return false
				end
				local m = FX.Mouse()
				local k = math.max(railScale.Scale, 0.1)
				local c = slot.AbsolutePosition + Vector2.new(slot.AbsoluteSize.X / 2, BTN / 2 * k)
				b.mx:Goal(math.clamp((m.X - c.X) / k * 0.28, -6, 6))
				b.my:Goal(math.clamp((m.Y - c.Y) / k * 0.28, -6, 6))
			end)
		end)
		hit.MouseLeave:Connect(function()
			hovered = false
			tab.Hover = false
			applyPill(tab, EASE.Med)
			b.sc:Goal(1)
			showTip(false)
		end)
		hit.MouseButton1Down:Connect(function()
			b.sc:Goal(0.92)
			tween(face, EASE.Drag, { Position = UDim2.fromOffset(0, 2) })
		end)
		hit.MouseButton1Up:Connect(function()
			b.sc:Goal(hovered and 1.12 or 1)
			tween(face, EASE.Fast, { Position = UDim2.new() })
		end)
		hit.Activated:Connect(function()
			local m = FX.Mouse()
			FX.Ripple(face, radius, Theme.Hot, m.X, m.Y)
			window:SelectTab(tab)
		end)

		onAccent(function(a)
			halo.BackgroundColor3 = a
			if tab.Active then applyPill(tab, EASE.Fast) end
		end)

		self.Tabs[idx] = tab
		if railShown then
			tab.Shown = true
			hit.Visible = true
			tween(shell, EASE.Rise, { Position = UDim2.new() })
			applyPill(tab, EASE.Rise)
		end
		if idx == 1 then self:SelectTab(tab) end
		return tab
	end
	self.Windows[#self.Windows + 1] = window

	task.defer(function() window:Open() end)
	return window
end


------------------------------------------------------------------------
-- configs
------------------------------------------------------------------------
local function fsOk()
	return type(writefile) == "function" and type(readfile) == "function" and type(isfolder) == "function"
		and type(makefolder) == "function" and type(listfiles) == "function"
end

local function ensureFolders()
	local base = Singularity.Folder
	if not isfolder(base) then makefolder(base) end
	if not isfolder(base .. "/configs") then makefolder(base .. "/configs") end
end

function Singularity:ListConfigs()
	local out = {}
	if not fsOk() then return out end
	pcall(function()
		ensureFolders()
		for _, path in ipairs(listfiles(self.Folder .. "/configs")) do
			local n = string.match(path, "([^/\\]+)%.json$")
			if n then out[#out + 1] = n end
		end
	end)
	table.sort(out)
	return out
end

function Singularity:SaveConfig(name)
	if not fsOk() then return false, "filesystem unavailable in this environment" end
	local data = {}
	for flag, el in pairs(self.Elements) do
		if not el.NoConfig and el.Encode then data[flag] = el:Encode() end
	end
	local ok, err = pcall(function()
		ensureFolders()
		writefile(self.Folder .. "/configs/" .. name .. ".json", HttpService:JSONEncode(data))
	end)
	return ok, err
end

function Singularity:LoadConfig(name)
	if not fsOk() then return false, "filesystem unavailable in this environment" end
	local path = self.Folder .. "/configs/" .. name .. ".json"
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	if not ok or type(data) ~= "table" then return false, "could not read " .. name end
	for flag, value in pairs(data) do
		local el = self.Elements[flag]
		if el and el.Decode and not el.NoConfig then pcall(el.Decode, el, value) end
	end
	return true
end

function Singularity:DeleteConfig(name)
	if type(delfile) ~= "function" then return false, "delfile unavailable" end
	return pcall(delfile, self.Folder .. "/configs/" .. name .. ".json")
end

------------------------------------------------------------------------
-- unload
------------------------------------------------------------------------
function Singularity:Unload()
	for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
	for _, f in ipairs(Cleanups) do pcall(f) end
	for _, g in ipairs(Guis) do pcall(function() g:Destroy() end) end
	table.clear(Connections)
	table.clear(Cleanups)
	table.clear(Guis)
	table.clear(AccentBinds)
	table.clear(Binds)
	table.clear(Features)
	self.Elements = {}
	self.Flags = {}
	self.Windows = {}
	NotifyGui, NotifyHolder = nil, nil
	if env.__Singularity == self then env.__Singularity = nil end
end


------------------------------------------------------------------------
-- quality, config sharing
------------------------------------------------------------------------
function Singularity:SetQuality(q)
	self.Quality = q
	if self._onQuality then pcall(self._onQuality, q) end
end

function Singularity:ExportConfig()
	local data = {}
	for flag, el in pairs(self.Elements) do
		if not el.NoConfig and el.Encode and string.sub(flag, 1, 2) ~= "__" then data[flag] = el:Encode() end
	end
	return HttpService:JSONEncode(data)
end

function Singularity:ImportConfig(text)
	if type(text) ~= "string" or text == "" then return false, "clipboard is empty" end
	local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
	if not ok or type(data) ~= "table" then return false, "that is not a Singularity setup" end
	local n = 0
	for flag, value in pairs(data) do
		local el = self.Elements[flag]
		if el and el.Decode and not el.NoConfig then
			pcall(el.Decode, el, value)
			n = n + 1
		end
	end
	return true, n
end

------------------------------------------------------------------------
-- DEMO  (set to false when you load this as a library)
-- every callback below is an empty hook: put your features there
------------------------------------------------------------------------
local RUN_DEMO = false

if RUN_DEMO then
	task.spawn(function()
		Singularity:Load({
			Title = "Singularity",
			Subtitle = "event horizon interface",
			Duration = 4.5,
		})

		local Window = Singularity:CreateWindow({ Title = "Singularity", Width = 780, Height = 480 })

		local combat = Window:CreateTab("Combat", { Icon = "crosshair", Description = "Targeting and trigger behaviour" })
		local aim = combat:CreateSection("Aim assist", "Left")
		aim:Toggle({ Name = "Enabled", Flag = "aim_on", Callback = function(v) --[[ hook ]] end })
		aim:Keybind({ Name = "Hold key", Default = Enum.KeyCode.E, Mode = "Hold", Flag = "aim_key", Callback = function(active) --[[ hook ]] end })
		aim:Slider({ Name = "Field of view", Min = 10, Max = 360, Default = 90, Suffix = " deg", Flag = "aim_fov", Callback = function(v) --[[ hook ]] end })
		aim:Slider({ Name = "Smoothing", Min = 0, Max = 100, Default = 35, Suffix = "%", Flag = "aim_smooth", Callback = function(v) --[[ hook ]] end })
		aim:Dropdown({ Name = "Target part", Options = { "Head", "Torso", "Nearest" }, Default = "Head", Flag = "aim_part", Callback = function(v) --[[ hook ]] end })
		local trig = combat:CreateSection("Trigger", "Right")
		trig:Toggle({ Name = "Enabled", Flag = "trig_on", Callback = function(v) --[[ hook ]] end })
		trig:Slider({ Name = "Delay", Min = 0, Max = 500, Default = 60, Increment = 5, Suffix = " ms", Flag = "trig_delay", Callback = function(v) --[[ hook ]] end })
		trig:Dropdown({ Name = "Checks", Options = { "Team", "Visible", "Alive", "Distance" }, Multi = true, Default = { "Team" }, Flag = "trig_checks", Callback = function(t) --[[ hook ]] end })

		local move = Window:CreateTab("Movement", { Icon = "footprints", Description = "Speed, jumping and traversal" })
		local speed = move:CreateSection("Speed", "Left")
		speed:Toggle({ Name = "Enabled", Flag = "speed_on", Callback = function(v) --[[ hook ]] end })
		speed:Slider({ Name = "Multiplier", Min = 1, Max = 5, Default = 1.5, Increment = 0.1, Suffix = "x", Flag = "speed_mult", Callback = function(v) --[[ hook ]] end })
		speed:Keybind({ Name = "Toggle key", Mode = "Toggle", Flag = "speed_key", Callback = function(state) --[[ hook ]] end })
		local jump = move:CreateSection("Jump", "Right")
		jump:Toggle({ Name = "Infinite jump", Flag = "jump_inf", Callback = function(v) --[[ hook ]] end })
		jump:Slider({ Name = "Power", Min = 50, Max = 300, Default = 50, Flag = "jump_power", Callback = function(v) --[[ hook ]] end })
		jump:Divider()
		jump:Label("Right-click a keybind chip to cycle Toggle / Hold / Press.")

		local vis = Window:CreateTab("Visuals", { Icon = "eye", Description = "Overlay and colours" })
		local esp = vis:CreateSection("Overlay", "Left")
		esp:Toggle({ Name = "Enabled", Flag = "esp_on", Callback = function(v) --[[ hook ]] end })
		esp:Dropdown({ Name = "Elements", Options = { "Box", "Name", "Health", "Distance", "Tracer" }, Multi = true, Default = { "Box", "Name" }, Flag = "esp_parts", Callback = function(t) --[[ hook ]] end })
		esp:Slider({ Name = "Max distance", Min = 100, Max = 5000, Default = 1500, Increment = 50, Suffix = " st", Flag = "esp_dist", Callback = function(v) --[[ hook ]] end })
		local colors = vis:CreateSection("Colors", "Right")
		colors:ColorPicker({ Name = "Enemy", Default = Color3.fromRGB(255, 82, 62), Flag = "col_enemy", Callback = function(c) --[[ hook ]] end })
		colors:ColorPicker({ Name = "Team", Default = Color3.fromRGB(96, 190, 255), Flag = "col_team", Callback = function(c) --[[ hook ]] end })

		local misc = Window:CreateTab("Misc", { Icon = "sparkles", Description = "Everything else" })
		local util = misc:CreateSection("Utility", "Left")
		util:Textbox({ Name = "Chat spam", Placeholder = "message", Flag = "misc_text", Callback = function(t) --[[ hook ]] end })
		util:Button({ Name = "Rejoin server", Callback = function() --[[ hook ]] end })
		util:Button({ Name = "Test notification", Callback = function()
			Singularity:Notify({ Title = "Signal received", Content = "Nothing is wired up yet - this is only the shell.", Type = "Success" })
		end })

		Singularity:Notify({ Title = "Singularity loaded", Content = "Press " .. keyText(Window.ToggleKey) .. " to collapse the interface.", Duration = 5 })
	end)
end

return Singularity