local profile_name = "Stereo-Forced"
local is_enabled = false

function toggle_profile()
	if is_enabled then
		-- Reset values to defaults
		mp.command("set ad-lavc-downmix no")
		mp.command("set audio-channels auto")
		mp.command("set af ''") -- Clear all audio filters
		is_enabled = false
		mp.osd_message("Profile disabled: " .. profile_name)
	else
		-- Apply the profile
		mp.command("apply-profile " .. profile_name)
		is_enabled = true
		mp.osd_message("Profile enabled: " .. profile_name)
	end
end

mp.add_key_binding("1", "toggle-stereo", toggle_profile)
